package notmuchbrowser

import (
	"bytes"
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"strings"
)

const capabilityKeyBytes = 32

var errInvalidCapability = errors.New("invalid or expired capability")

type capabilityPurpose string

const (
	purposeAttachment capabilityPurpose = "attachment"
	purposeArchive    capabilityPurpose = "attachments-zip"
	purposeInline     capabilityPurpose = "inline-image"
)

type capabilityPayload struct {
	Version   int               `json:"v"`
	Purpose   capabilityPurpose `json:"p"`
	MessageID string            `json:"m"`
	Duplicate int               `json:"d"`
	Part      int               `json:"n,omitempty"`
	FileName  string            `json:"f,omitempty"`
	MediaType string            `json:"t,omitempty"`
}

type capabilitySigner struct {
	key []byte
}

func newCapabilitySigner() (capabilitySigner, error) {
	return newCapabilitySignerFrom(rand.Reader)
}

func newCapabilitySignerFrom(reader io.Reader) (capabilitySigner, error) {
	key := make([]byte, capabilityKeyBytes)
	if _, err := io.ReadFull(reader, key); err != nil {
		return capabilitySigner{}, fmt.Errorf("generate capability key: %w", err)
	}
	return newCapabilitySignerWithKey(key)
}

func newCapabilitySignerWithKey(key []byte) (capabilitySigner, error) {
	if len(key) < capabilityKeyBytes {
		return capabilitySigner{}, fmt.Errorf("capability key must contain at least %d bytes", capabilityKeyBytes)
	}
	owned := append([]byte(nil), key...)
	return capabilitySigner{key: owned}, nil
}

func (s capabilitySigner) Sign(payload capabilityPayload) (string, error) {
	payload.Version = 1
	if err := validateCapabilityPayload(payload); err != nil {
		return "", err
	}
	raw, err := json.Marshal(payload)
	if err != nil {
		return "", fmt.Errorf("marshal capability: %w", err)
	}
	encoded := base64.RawURLEncoding.EncodeToString(raw)
	signature := s.signature(encoded)
	return encoded + "." + base64.RawURLEncoding.EncodeToString(signature), nil
}

func (s capabilitySigner) Verify(token string, purpose capabilityPurpose) (capabilityPayload, error) {
	if len(token) == 0 || len(token) > 8192 {
		return capabilityPayload{}, errInvalidCapability
	}
	encoded, signatureText, ok := strings.Cut(token, ".")
	if !ok || encoded == "" || signatureText == "" || strings.Contains(signatureText, ".") {
		return capabilityPayload{}, errInvalidCapability
	}
	signature, err := base64.RawURLEncoding.DecodeString(signatureText)
	if err != nil || !hmac.Equal(signature, s.signature(encoded)) {
		return capabilityPayload{}, errInvalidCapability
	}
	raw, err := base64.RawURLEncoding.DecodeString(encoded)
	if err != nil {
		return capabilityPayload{}, errInvalidCapability
	}
	decoder := json.NewDecoder(bytes.NewReader(raw))
	decoder.DisallowUnknownFields()
	var payload capabilityPayload
	if err := decoder.Decode(&payload); err != nil {
		return capabilityPayload{}, errInvalidCapability
	}
	if err := decoder.Decode(&struct{}{}); err != io.EOF {
		return capabilityPayload{}, errInvalidCapability
	}
	if payload.Purpose != purpose || validateCapabilityPayload(payload) != nil {
		return capabilityPayload{}, errInvalidCapability
	}
	return payload, nil
}

func (s capabilitySigner) signature(encoded string) []byte {
	mac := hmac.New(sha256.New, s.key)
	_, _ = mac.Write([]byte(encoded))
	return mac.Sum(nil)
}

func validateCapabilityPayload(payload capabilityPayload) error {
	if payload.Version != 1 || payload.MessageID == "" || len(payload.MessageID) > defaultMaxMessageIDSize || payload.Duplicate < 0 {
		return errInvalidCapability
	}
	switch payload.Purpose {
	case purposeAttachment, purposeInline:
		if payload.Part <= 0 || len(payload.FileName) > 1024 || len(payload.MediaType) > 255 {
			return errInvalidCapability
		}
	case purposeArchive:
		if payload.Part != 0 || payload.FileName != "" || payload.MediaType != "" {
			return errInvalidCapability
		}
	default:
		return errInvalidCapability
	}
	return nil
}
