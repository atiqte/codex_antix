package notmuchbrowser

import (
	"fmt"
	stdhtml "html"
	"io"
	"net/url"
	"regexp"
	"strings"
	"unicode"

	xhtml "golang.org/x/net/html"
)

const (
	maxEmailHTMLBytes = 32 << 20
	maxHTMLTokenBytes = 8 << 20
)

type imageMode string

const (
	imagesBlocked  imageMode = "blocked"
	imagesEmbedded imageMode = "embedded"
	imagesRemote   imageMode = "remote"
)

var cidReferencePattern = regexp.MustCompile(`(?i)cid:[^\s"'<>(),]+`)

func parseImageMode(raw string) imageMode {
	switch imageMode(strings.ToLower(strings.TrimSpace(raw))) {
	case imagesEmbedded:
		return imagesEmbedded
	case imagesRemote:
		return imagesRemote
	default:
		return imagesBlocked
	}
}

func sanitizeEmailHTML(body string, mode imageMode, origin string, cidURLs map[string]string) (string, error) {
	if len(body) > maxEmailHTMLBytes {
		return "", fmt.Errorf("email HTML exceeds %d bytes", maxEmailHTMLBytes)
	}

	tokenizer := xhtml.NewTokenizer(strings.NewReader(body))
	tokenizer.SetMaxBuf(maxHTMLTokenBytes)
	var out strings.Builder
	out.Grow(min(len(body)+512, maxEmailHTMLBytes))
	out.WriteString(`<meta http-equiv="Content-Security-Policy" content="`)
	out.WriteString(stdhtml.EscapeString(emailFrameCSP(mode, origin)))
	out.WriteString(`">`)

	dropDepth := 0
	dropName := ""
	styleDepth := 0
	for {
		tokenType := tokenizer.Next()
		if tokenType == xhtml.ErrorToken {
			if err := tokenizer.Err(); err != nil && err != io.EOF {
				return "", fmt.Errorf("parse email HTML: %w", err)
			}
			break
		}
		token := tokenizer.Token()
		name := strings.ToLower(token.Data)

		if dropDepth > 0 {
			switch tokenType {
			case xhtml.StartTagToken:
				if name == dropName {
					dropDepth++
				}
			case xhtml.EndTagToken:
				if name == dropName {
					dropDepth--
					if dropDepth == 0 {
						dropName = ""
					}
				}
			}
			continue
		}

		switch tokenType {
		case xhtml.StartTagToken, xhtml.SelfClosingTagToken:
			if shouldDropEmailElement(name, token.Attr) || name == "svg" && mode == imagesBlocked {
				if name == "svg" && mode == imagesBlocked {
					out.WriteString(`<span role="img" aria-label="Embedded SVG blocked">[embedded SVG blocked]</span>`)
				}
				if tokenType == xhtml.StartTagToken && droppedElementHasBody(name) {
					dropDepth = 1
					dropName = name
				}
				continue
			}
			token.Attr = sanitizeEmailAttributes(token.Attr, mode, cidURLs)
			out.WriteString(token.String())
			if name == "style" && tokenType == xhtml.StartTagToken {
				styleDepth++
			}
		case xhtml.EndTagToken:
			if name == "style" && styleDepth > 0 {
				styleDepth--
			}
			out.WriteString(token.String())
		case xhtml.TextToken:
			if styleDepth > 0 {
				token.Data = rewriteCIDReferences(token.Data, mode, cidURLs)
			}
			out.WriteString(token.String())
		case xhtml.DoctypeToken:
			out.WriteString(token.String())
		}
	}
	return out.String(), nil
}

func droppedElementHasBody(name string) bool {
	switch name {
	case "script", "iframe", "frameset", "object", "form", "foreignobject", "svg":
		return true
	default:
		return false
	}
}

func shouldDropEmailElement(name string, attrs []xhtml.Attribute) bool {
	switch name {
	case "script", "iframe", "frame", "frameset", "object", "embed", "form", "base", "link", "foreignobject":
		return true
	case "meta":
		for _, attr := range attrs {
			if strings.EqualFold(attr.Key, "http-equiv") {
				value := strings.ToLower(strings.TrimSpace(attr.Val))
				if value == "content-security-policy" || value == "refresh" {
					return true
				}
			}
		}
	}
	return false
}

func sanitizeEmailAttributes(attrs []xhtml.Attribute, mode imageMode, cidURLs map[string]string) []xhtml.Attribute {
	out := attrs[:0]
	for _, attr := range attrs {
		key := strings.ToLower(attr.Key)
		if strings.HasPrefix(key, "on") || key == "srcdoc" || key == "formaction" {
			continue
		}
		value := attr.Val
		switch key {
		case "src", "srcset", "background", "href", "xlink:href", "poster", "style":
			value = rewriteCIDReferences(value, mode, cidURLs)
		}
		trimmed := strings.ToLower(strings.TrimSpace(value))
		if strings.HasPrefix(trimmed, "javascript:") || strings.HasPrefix(trimmed, "vbscript:") {
			continue
		}
		attr.Val = value
		out = append(out, attr)
	}
	return out
}

func rewriteCIDReferences(value string, mode imageMode, cidURLs map[string]string) string {
	matches := cidReferencePattern.FindAllStringIndex(value, -1)
	if len(matches) == 0 {
		return value
	}
	var out strings.Builder
	last := 0
	for _, match := range matches {
		out.WriteString(value[last:match[0]])
		reference := value[match[0]:match[1]]
		if insideDataURI(value, match[0]) {
			out.WriteString(reference)
			last = match[1]
			continue
		}
		if mode == imagesBlocked {
			out.WriteString("about:blank#blocked-image")
			last = match[1]
			continue
		}
		cid := normalizeContentID(reference)
		if replacement := cidURLs[strings.ToLower(cid)]; replacement != "" {
			out.WriteString(replacement)
		} else {
			out.WriteString("about:blank#missing-cid")
		}
		last = match[1]
	}
	out.WriteString(value[last:])
	return out.String()
}

func insideDataURI(value string, offset int) bool {
	prefix := strings.ToLower(value[:offset])
	start := strings.LastIndex(prefix, "data:")
	if start < 0 {
		return false
	}
	for _, delimiter := range value[start+5 : offset] {
		if delimiter == '\'' || delimiter == '"' || delimiter == ')' || unicode.IsSpace(delimiter) {
			return false
		}
	}
	return true
}

func normalizeContentID(value string) string {
	value = strings.TrimSpace(value)
	if len(value) >= 4 && strings.EqualFold(value[:4], "cid:") {
		value = value[4:]
	}
	if decoded, err := url.PathUnescape(value); err == nil {
		value = decoded
	}
	value = strings.TrimSpace(value)
	value = strings.TrimPrefix(value, "<")
	value = strings.TrimSuffix(value, ">")
	return strings.TrimSpace(value)
}

func emailFrameCSP(mode imageMode, origin string) string {
	imageSources := "'none'"
	if mode == imagesEmbedded {
		imageSources = origin + " data:"
	} else if mode == imagesRemote {
		imageSources = origin + " data: http: https:"
	}
	return "default-src 'none'; img-src " + imageSources + "; style-src 'unsafe-inline'; script-src 'none'; object-src 'none'; base-uri 'none'; form-action 'none'; font-src 'none'; connect-src 'none'; media-src 'none'; frame-src 'none'; child-src 'none'"
}
