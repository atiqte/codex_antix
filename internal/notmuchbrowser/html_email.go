package notmuchbrowser

import (
	"fmt"
	stdhtml "html"
	"io"
	"net/url"
	pathpkg "path"
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
var cssURLPattern = regexp.MustCompile(`(?i)url\(\s*['"]?([^'")]+)['"]?\s*\)`)

type imageReferenceSet struct {
	CIDs  map[string]bool
	Names map[string]bool
}

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
	return sanitizeEmailHTMLWithResources(body, mode, origin, cidURLs, nil)
}

func sanitizeEmailHTMLWithResources(body string, mode imageMode, origin string, cidURLs map[string]string, nameURLs map[string]string) (string, error) {
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
	out.WriteString(`<style id="notmuch-browser-email-defaults">html,body{font-family:Aptos,"Segoe UI",Carlito,Arial,sans-serif}img{max-width:100%;height:auto}</style>`)

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
			token.Attr = sanitizeEmailAttributes(name, token.Attr, mode, cidURLs, nameURLs)
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
				token.Data = rewriteStyleImageReferences(token.Data, mode, cidURLs, nameURLs)
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

func sanitizeEmailAttributes(element string, attrs []xhtml.Attribute, mode imageMode, cidURLs map[string]string, nameURLs map[string]string) []xhtml.Attribute {
	out := attrs[:0]
	for _, attr := range attrs {
		key := strings.ToLower(attr.Key)
		if strings.HasPrefix(key, "on") || key == "srcdoc" || key == "formaction" {
			continue
		}
		value := attr.Val
		switch {
		case key == "style":
			value = rewriteStyleImageReferences(value, mode, cidURLs, nameURLs)
		case isImageReferenceAttribute(element, key) && key == "srcset":
			value = rewriteSrcsetImageReferences(value, mode, cidURLs, nameURLs)
		case isImageReferenceAttribute(element, key):
			value = rewriteDirectImageReference(value, mode, cidURLs, nameURLs)
		case key == "src" || key == "href" || key == "xlink:href" || key == "poster" || key == "background":
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

func collectImageReferences(body string) imageReferenceSet {
	references := imageReferenceSet{CIDs: map[string]bool{}, Names: map[string]bool{}}
	tokenizer := xhtml.NewTokenizer(strings.NewReader(body))
	tokenizer.SetMaxBuf(maxHTMLTokenBytes)
	styleDepth := 0
	for {
		tokenType := tokenizer.Next()
		if tokenType == xhtml.ErrorToken {
			break
		}
		token := tokenizer.Token()
		element := strings.ToLower(token.Data)
		switch tokenType {
		case xhtml.StartTagToken, xhtml.SelfClosingTagToken:
			for _, attr := range token.Attr {
				key := strings.ToLower(attr.Key)
				switch {
				case key == "style":
					collectStyleImageReferences(attr.Val, &references)
				case isImageReferenceAttribute(element, key) && key == "srcset":
					collectSrcsetImageReferences(attr.Val, &references)
				case isImageReferenceAttribute(element, key):
					collectDirectImageReference(attr.Val, &references)
				}
			}
			if element == "style" && tokenType == xhtml.StartTagToken {
				styleDepth++
			}
		case xhtml.EndTagToken:
			if element == "style" && styleDepth > 0 {
				styleDepth--
			}
		case xhtml.TextToken:
			if styleDepth > 0 {
				collectStyleImageReferences(token.Data, &references)
			}
		}
	}
	return references
}

func isImageReferenceAttribute(element string, key string) bool {
	switch key {
	case "background":
		return true
	case "src":
		return element == "img" || element == "input"
	case "srcset":
		return element == "img" || element == "source"
	case "poster":
		return element == "video"
	case "href", "xlink:href":
		return element == "image" || element == "use"
	default:
		return false
	}
}

func collectDirectImageReference(value string, references *imageReferenceSet) {
	collectContentIDs(value, references)
	if name, relative := relativeImageName(value); relative && name != "" {
		references.Names[name] = true
	}
}

func collectSrcsetImageReferences(value string, references *imageReferenceSet) {
	collectContentIDs(value, references)
	if strings.Contains(strings.ToLower(value), "data:") {
		return
	}
	for _, candidate := range strings.Split(value, ",") {
		fields := strings.Fields(strings.TrimSpace(candidate))
		if len(fields) > 0 {
			collectDirectImageReference(fields[0], references)
		}
	}
}

func collectContentIDs(value string, references *imageReferenceSet) {
	for _, match := range cidReferencePattern.FindAllStringIndex(value, -1) {
		if insideDataURI(value, match[0]) {
			continue
		}
		if cid := normalizeContentID(value[match[0]:match[1]]); cid != "" {
			references.CIDs[strings.ToLower(cid)] = true
		}
	}
}

func collectStyleImageReferences(value string, references *imageReferenceSet) {
	for _, match := range cssURLPattern.FindAllStringSubmatch(value, -1) {
		if len(match) > 1 {
			collectDirectImageReference(match[1], references)
		}
	}
}

func rewriteDirectImageReference(value string, mode imageMode, cidURLs map[string]string, nameURLs map[string]string) string {
	rewritten := rewriteCIDReferences(value, mode, cidURLs)
	if rewritten != value {
		return rewritten
	}
	name, relative := relativeImageName(value)
	if !relative {
		return value
	}
	if mode == imagesBlocked {
		return "about:blank#blocked-image"
	}
	if replacement := nameURLs[name]; name != "" && replacement != "" {
		return replacement
	}
	return "about:blank#missing-inline-image"
}

func rewriteSrcsetImageReferences(value string, mode imageMode, cidURLs map[string]string, nameURLs map[string]string) string {
	value = rewriteCIDReferences(value, mode, cidURLs)
	if strings.Contains(strings.ToLower(value), "data:") {
		return value
	}
	parts := strings.Split(value, ",")
	for i, candidate := range parts {
		leading := candidate[:len(candidate)-len(strings.TrimLeft(candidate, " \t\r\n"))]
		fields := strings.Fields(strings.TrimSpace(candidate))
		if len(fields) == 0 {
			continue
		}
		fields[0] = rewriteDirectImageReference(fields[0], mode, cidURLs, nameURLs)
		parts[i] = leading + strings.Join(fields, " ")
	}
	return strings.Join(parts, ",")
}

func rewriteStyleImageReferences(value string, mode imageMode, cidURLs map[string]string, nameURLs map[string]string) string {
	value = rewriteCIDReferences(value, mode, cidURLs)
	return cssURLPattern.ReplaceAllStringFunc(value, func(match string) string {
		parts := cssURLPattern.FindStringSubmatch(match)
		if len(parts) < 2 {
			return match
		}
		rewritten := rewriteDirectImageReference(parts[1], mode, cidURLs, nameURLs)
		return "url(\"" + strings.ReplaceAll(rewritten, "\"", "%22") + "\")"
	})
}

func relativeImageName(value string) (string, bool) {
	value = strings.TrimSpace(strings.Trim(value, "\"'"))
	if value == "" {
		return "", false
	}
	lower := strings.ToLower(value)
	for _, prefix := range []string{"cid:", "data:", "http:", "https:", "ftp:", "about:", "blob:", "//", "#"} {
		if strings.HasPrefix(lower, prefix) {
			return "", false
		}
	}
	parsed, err := url.Parse(value)
	if err != nil || parsed.IsAbs() || parsed.Host != "" {
		return "", false
	}
	pathValue, err := url.PathUnescape(parsed.Path)
	if err != nil {
		return "", true
	}
	if pathValue == "" || strings.HasPrefix(pathValue, "/") || strings.Contains(pathValue, "\\") || strings.ContainsRune(pathValue, '\x00') {
		return "", true
	}
	for _, segment := range strings.Split(pathValue, "/") {
		if segment == ".." {
			return "", true
		}
	}
	name := strings.ToLower(sanitizeFilename(pathpkg.Base(pathValue)))
	return name, true
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
