// Package mtls manages the agent's internal certificate authority.
//
// On first run the agent generates an ECDSA P-256 self-signed CA, plus a
// server certificate signed by that CA. Both live under --cert-dir
// (default /etc/vpn-agent). Client certificates are issued either via
// the CLI (`vpn-agent issue-cert`) or, in a future milestone, via an
// enrollment HTTP endpoint.
//
// We use the standard library's crypto/x509 only — no third-party PKI
// dependencies. The attack surface is intentionally tiny.
package mtls

import (
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/tls"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/pem"
	"fmt"
	"math/big"
	"net"
	"os"
	"path/filepath"
	"time"
)

const (
	caCertFile  = "ca.pem"
	caKeyFile   = "ca.key"
	srvCertFile = "server.pem"
	srvKeyFile  = "server.key"

	caValidity     = 10 * 365 * 24 * time.Hour // 10 years
	serverValidity = 5 * 365 * 24 * time.Hour  // 5 years
	clientValidity = 1 * 365 * 24 * time.Hour  // 1 year
)

// CA holds the in-memory representation of the local CA: parsed cert,
// raw DER, private key, and a CertPool ready to use as ClientCAs in a
// tls.Config.
type CA struct {
	Cert    *x509.Certificate
	CertDER []byte
	Key     *ecdsa.PrivateKey
	Pool    *x509.CertPool
}

// LoadOrCreateCA loads a CA from dir if it exists, otherwise creates a
// fresh one. The directory is created with mode 0700 if it does not
// already exist.
func LoadOrCreateCA(dir string) (*CA, error) {
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return nil, fmt.Errorf("mkdir cert-dir: %w", err)
	}
	certPath := filepath.Join(dir, caCertFile)
	keyPath := filepath.Join(dir, caKeyFile)

	if fileExists(certPath) && fileExists(keyPath) {
		return loadCA(certPath, keyPath)
	}
	return createCA(certPath, keyPath)
}

func loadCA(certPath, keyPath string) (*CA, error) {
	certPEM, err := os.ReadFile(certPath)
	if err != nil {
		return nil, fmt.Errorf("read CA cert: %w", err)
	}
	keyPEM, err := os.ReadFile(keyPath)
	if err != nil {
		return nil, fmt.Errorf("read CA key: %w", err)
	}

	certBlock, _ := pem.Decode(certPEM)
	if certBlock == nil || certBlock.Type != "CERTIFICATE" {
		return nil, fmt.Errorf("invalid CA cert PEM at %s", certPath)
	}
	cert, err := x509.ParseCertificate(certBlock.Bytes)
	if err != nil {
		return nil, fmt.Errorf("parse CA cert: %w", err)
	}

	keyBlock, _ := pem.Decode(keyPEM)
	if keyBlock == nil || keyBlock.Type != "EC PRIVATE KEY" {
		return nil, fmt.Errorf("invalid CA key PEM at %s", keyPath)
	}
	key, err := x509.ParseECPrivateKey(keyBlock.Bytes)
	if err != nil {
		return nil, fmt.Errorf("parse CA key: %w", err)
	}

	pool := x509.NewCertPool()
	pool.AddCert(cert)
	return &CA{Cert: cert, CertDER: certBlock.Bytes, Key: key, Pool: pool}, nil
}

func createCA(certPath, keyPath string) (*CA, error) {
	key, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		return nil, fmt.Errorf("generate CA key: %w", err)
	}
	serial, err := randSerial()
	if err != nil {
		return nil, err
	}
	template := &x509.Certificate{
		SerialNumber: serial,
		Subject: pkix.Name{
			CommonName:   "ICD360S VPN Agent CA",
			Organization: []string{"ICD360S e.V."},
		},
		NotBefore:             time.Now().Add(-1 * time.Hour),
		NotAfter:              time.Now().Add(caValidity),
		KeyUsage:              x509.KeyUsageCertSign | x509.KeyUsageCRLSign | x509.KeyUsageDigitalSignature,
		BasicConstraintsValid: true,
		IsCA:                  true,
		MaxPathLen:            0,
		MaxPathLenZero:        true,
	}
	der, err := x509.CreateCertificate(rand.Reader, template, template, &key.PublicKey, key)
	if err != nil {
		return nil, fmt.Errorf("create CA cert: %w", err)
	}
	cert, err := x509.ParseCertificate(der)
	if err != nil {
		return nil, fmt.Errorf("re-parse CA cert: %w", err)
	}

	if err := writePEM(certPath, "CERTIFICATE", der, 0o644); err != nil {
		return nil, fmt.Errorf("write CA cert: %w", err)
	}
	keyDER, err := x509.MarshalECPrivateKey(key)
	if err != nil {
		return nil, fmt.Errorf("marshal CA key: %w", err)
	}
	if err := writePEM(keyPath, "EC PRIVATE KEY", keyDER, 0o600); err != nil {
		return nil, fmt.Errorf("write CA key: %w", err)
	}

	pool := x509.NewCertPool()
	pool.AddCert(cert)
	return &CA{Cert: cert, CertDER: der, Key: key, Pool: pool}, nil
}

// LoadOrIssueServerCert returns a tls.Certificate for the agent's HTTPS
// listener. If a cert + key pair already exists in dir, they are loaded.
// Otherwise a fresh server cert is issued, signed by the CA, with a SAN
// matching the host portion of listenAddr.
func (ca *CA) LoadOrIssueServerCert(dir, listenAddr string) (tls.Certificate, error) {
	certPath := filepath.Join(dir, srvCertFile)
	keyPath := filepath.Join(dir, srvKeyFile)
	if fileExists(certPath) && fileExists(keyPath) {
		return tls.LoadX509KeyPair(certPath, keyPath)
	}

	host, _, err := net.SplitHostPort(listenAddr)
	if err != nil {
		return tls.Certificate{}, fmt.Errorf("invalid listen addr: %w", err)
	}

	key, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		return tls.Certificate{}, err
	}
	serial, err := randSerial()
	if err != nil {
		return tls.Certificate{}, err
	}
	template := &x509.Certificate{
		SerialNumber: serial,
		Subject: pkix.Name{
			CommonName:   "vpn-agent",
			Organization: []string{"ICD360S e.V."},
		},
		NotBefore:   time.Now().Add(-1 * time.Hour),
		NotAfter:    time.Now().Add(serverValidity),
		KeyUsage:    x509.KeyUsageDigitalSignature | x509.KeyUsageKeyEncipherment,
		ExtKeyUsage: []x509.ExtKeyUsage{x509.ExtKeyUsageServerAuth},
	}
	if ip := net.ParseIP(host); ip != nil {
		template.IPAddresses = []net.IP{ip}
	} else {
		template.DNSNames = []string{host}
	}

	der, err := x509.CreateCertificate(rand.Reader, template, ca.Cert, &key.PublicKey, ca.Key)
	if err != nil {
		return tls.Certificate{}, fmt.Errorf("create server cert: %w", err)
	}
	if err := writePEM(certPath, "CERTIFICATE", der, 0o644); err != nil {
		return tls.Certificate{}, err
	}
	keyDER, err := x509.MarshalECPrivateKey(key)
	if err != nil {
		return tls.Certificate{}, err
	}
	if err := writePEM(keyPath, "EC PRIVATE KEY", keyDER, 0o600); err != nil {
		return tls.Certificate{}, err
	}
	return tls.LoadX509KeyPair(certPath, keyPath)
}

// IssueClientCertPEM generates a fresh client cert signed by the CA
// and returns the cert PEM, key PEM, and CA PEM as in-memory byte
// slices. No disk I/O.
//
// Used by `vpn-agent issue-bundle` to package an enrollment payload
// for the Flutter admin app, and (via IssueClientCert) by the
// `vpn-agent issue-cert` subcommand which still writes to disk.
func (ca *CA) IssueClientCertPEM(name string) (certPEM, keyPEM, caPEM []byte, err error) {
	key, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		return nil, nil, nil, err
	}
	serial, err := randSerial()
	if err != nil {
		return nil, nil, nil, err
	}
	template := &x509.Certificate{
		SerialNumber: serial,
		Subject: pkix.Name{
			CommonName:   name,
			Organization: []string{"ICD360S VPN admin"},
		},
		NotBefore:   time.Now().Add(-1 * time.Hour),
		NotAfter:    time.Now().Add(clientValidity),
		KeyUsage:    x509.KeyUsageDigitalSignature,
		ExtKeyUsage: []x509.ExtKeyUsage{x509.ExtKeyUsageClientAuth},
	}
	certDER, err := x509.CreateCertificate(rand.Reader, template, ca.Cert, &key.PublicKey, ca.Key)
	if err != nil {
		return nil, nil, nil, fmt.Errorf("create client cert: %w", err)
	}
	keyDER, err := x509.MarshalECPrivateKey(key)
	if err != nil {
		return nil, nil, nil, err
	}

	certPEM = pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: certDER})
	keyPEM = pem.EncodeToMemory(&pem.Block{Type: "EC PRIVATE KEY", Bytes: keyDER})
	caPEM = pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: ca.CertDER})
	return certPEM, keyPEM, caPEM, nil
}

// IssueClientCert generates a fresh client cert signed by the CA and
// writes three files into outDir:
//
//	<sanitized-name>.pem      The client cert
//	<sanitized-name>.key      The client private key (mode 0600)
//	<sanitized-name>-ca.pem   The CA cert (so the client can verify the server)
//
// Thin wrapper around IssueClientCertPEM.
func (ca *CA) IssueClientCert(name, outDir string) error {
	if err := os.MkdirAll(outDir, 0o700); err != nil {
		return fmt.Errorf("mkdir out: %w", err)
	}
	certPEM, keyPEM, caPEM, err := ca.IssueClientCertPEM(name)
	if err != nil {
		return err
	}
	base := filepath.Join(outDir, sanitize(name))
	if err := os.WriteFile(base+".pem", certPEM, 0o644); err != nil {
		return err
	}
	if err := os.WriteFile(base+".key", keyPEM, 0o600); err != nil {
		return err
	}
	if err := os.WriteFile(base+"-ca.pem", caPEM, 0o644); err != nil {
		return err
	}
	return nil
}

func writePEM(path, blockType string, der []byte, mode os.FileMode) error {
	f, err := os.OpenFile(path, os.O_CREATE|os.O_TRUNC|os.O_WRONLY, mode)
	if err != nil {
		return err
	}
	defer f.Close()
	return pem.Encode(f, &pem.Block{Type: blockType, Bytes: der})
}

func fileExists(p string) bool {
	_, err := os.Stat(p)
	return err == nil
}

func randSerial() (*big.Int, error) {
	max := new(big.Int).Lsh(big.NewInt(1), 128)
	return rand.Int(rand.Reader, max)
}

// sanitize replaces any character that is not [A-Za-z0-9_-] with '_'
// so the name can be used in a filesystem path.
func sanitize(name string) string {
	out := make([]byte, len(name))
	for i := 0; i < len(name); i++ {
		c := name[i]
		switch {
		case c >= 'a' && c <= 'z',
			c >= 'A' && c <= 'Z',
			c >= '0' && c <= '9',
			c == '-' || c == '_':
			out[i] = c
		default:
			out[i] = '_'
		}
	}
	return string(out)
}
