package notmuchbrowser

import (
	"html/template"
	"net/url"
	"strconv"
)

type pageView struct {
	Title      string
	Query      string
	Error      string
	SearchPage SearchPage
}

type messageView struct {
	Error  string
	Detail MessageDetail
}

type statusView struct {
	Error      string
	Status     Status
	TunnelHint string
}

var templates = template.Must(template.New("notmuch-browser").Funcs(template.FuncMap{
	"add":            func(a, b int) int { return a + b },
	"displayLimit":   displayLimit,
	"firstShown":     firstShown,
	"hasNext":        hasNext,
	"hasPrev":        hasPrev,
	"nextOffset":     nextOffset,
	"prevOffset":     prevOffset,
	"searchURL":      searchURL,
	"messageURL":     messageURL,
	"selectedDup":    selectedDup,
	"formatFileCount": formatFileCount,
	"dictTitle":      func(title string) pageView { return pageView{Title: title} },
}).Parse(templateText))

func displayLimit(page SearchPage) int {
	if page.Limit > 0 {
		return page.Limit
	}
	return 50
}

func firstShown(page SearchPage) int {
	if len(page.Results) == 0 {
		return 0
	}
	return page.Offset + 1
}

func nextOffset(page SearchPage) int {
	return page.Offset + len(page.Results)
}

func prevOffset(page SearchPage) int {
	limit := displayLimit(page)
	offset := page.Offset - limit
	if offset < 0 {
		return 0
	}
	return offset
}

func hasPrev(page SearchPage) bool {
	return page.Offset > 0
}

func hasNext(page SearchPage) bool {
	return nextOffset(page) < page.Counts.Messages
}

func searchURL(query string, offset int, limit int) string {
	values := url.Values{}
	values.Set("q", query)
	values.Set("offset", strconv.Itoa(offset))
	values.Set("limit", strconv.Itoa(limit))
	return "/search?" + values.Encode()
}

func messageURL(id string, duplicate int) string {
	values := url.Values{}
	values.Set("id", id)
	if duplicate > 0 {
		values.Set("dup", strconv.Itoa(duplicate))
	}
	return "/message?" + values.Encode()
}

func selectedDup(current int, expected int) bool {
	return current == expected
}

func formatFileCount(count int) string {
	if count <= 0 {
		return "?"
	}
	return strconv.Itoa(count)
}

const templateText = `
{{define "top"}}
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>{{.Title}} - notmuch browser</title>
  <link rel="stylesheet" href="/static/app.css">
  <script src="/static/htmx.min.js" defer></script>
</head>
<body>
<header class="app-header">
  <a class="brand" href="/">notmuch browser</a>
  <nav>
    <a href="/">Search</a>
    <a href="/status">Status</a>
  </nav>
  <span class="mode">read-only | single email</span>
</header>
<main class="shell">
{{end}}

{{define "bottom"}}
</main>
</body>
</html>
{{end}}

{{define "page"}}
{{template "top" .}}
<section class="search-panel">
  <form class="search-form" action="/search" method="get" hx-get="/search" hx-target="#results" hx-push-url="true">
    <label class="field">
      <span>Query</span>
      <input id="query" name="q" type="search" value="{{.Query}}" autocomplete="off" spellcheck="false" autofocus>
    </label>
    <input type="hidden" name="limit" value="{{displayLimit .SearchPage}}">
    <button type="submit">Search</button>
  </form>
  <div class="examples">
    <a href="/search?q=tag%3Ainbox">tag:inbox</a>
    <a href="/search?q=from%3Atagindustries.com.sg">from:tagindustries.com.sg</a>
    <a href="/search?q=date%3A2026..2026%20and%20tag%3Aattachment">date:2026..2026 and tag:attachment</a>
  </div>
</section>
<section id="results" class="results" aria-live="polite">
  {{template "results" .}}
</section>
{{template "bottom" .}}
{{end}}

{{define "results"}}
{{if .Error}}
<div class="notice bad">{{.Error}}</div>
{{else}}
<div class="result-toolbar">
  <div>
    <strong>{{.SearchPage.Counts.Messages}}</strong> messages |
    <strong>{{.SearchPage.Counts.Files}}</strong> files
    {{if .SearchPage.Results}}
      | showing {{firstShown .SearchPage}}-{{nextOffset .SearchPage}}
    {{end}}
  </div>
  <div class="code">{{.SearchPage.Query}}</div>
</div>
{{if .SearchPage.Results}}
<table class="result-table">
  <thead>
    <tr>
      <th>Date</th>
      <th>From</th>
      <th>Subject / Message-ID</th>
      <th>Tags</th>
      <th>Files</th>
    </tr>
  </thead>
  <tbody>
  {{range .SearchPage.Results}}
    <tr>
      <td class="date">{{if .DateRelative}}{{.DateRelative}}{{else}}{{.Date}}{{end}}</td>
      <td>{{.From}}</td>
      <td>
        <a class="subject" href="{{messageURL .ID 0}}">{{.Subject}}</a>
        <div class="path">{{.ID}}</div>
      </td>
      <td class="tags">
        {{range .Tags}}<span>{{.}}</span>{{end}}
      </td>
      <td class="file-count">{{formatFileCount .FileCount}}</td>
    </tr>
  {{end}}
  </tbody>
</table>
<div class="pager">
  {{if hasPrev .SearchPage}}
    <a class="button" href="{{searchURL .SearchPage.Query (prevOffset .SearchPage) (displayLimit .SearchPage)}}" hx-get="{{searchURL .SearchPage.Query (prevOffset .SearchPage) (displayLimit .SearchPage)}}" hx-target="#results" hx-push-url="true">Previous</a>
  {{end}}
  {{if hasNext .SearchPage}}
    <a class="button" href="{{searchURL .SearchPage.Query (nextOffset .SearchPage) (displayLimit .SearchPage)}}" hx-get="{{searchURL .SearchPage.Query (nextOffset .SearchPage) (displayLimit .SearchPage)}}" hx-target="#results" hx-push-url="true">Next</a>
  {{end}}
</div>
{{else}}
<div class="notice">No results.</div>
{{end}}
{{end}}
{{end}}

{{define "messagePage"}}
{{template "top" (dictTitle "Message")}}
{{if .Error}}
  <div class="notice bad">{{.Error}}</div>
{{else}}
<p><a class="button" href="/">Back to search</a></p>
<article class="message">
  <header class="message-meta">
    <h1>{{.Detail.Summary.Subject}}</h1>
    <dl>
      <dt>From</dt><dd>{{.Detail.Summary.From}}</dd>
      <dt>To</dt><dd>{{.Detail.Summary.To}}</dd>
      <dt>Date</dt><dd>{{.Detail.Summary.Date}}</dd>
      <dt>Message-ID</dt><dd class="path">{{.Detail.Summary.ID}}</dd>
      {{if .Detail.SelectedFile}}<dt>Selected file</dt><dd class="path">{{.Detail.SelectedFile}}</dd>{{end}}
    </dl>
    <div class="tags">{{range .Detail.Summary.Tags}}<span>{{.}}</span>{{end}}</div>
    {{if .Detail.DuplicateNote}}
    <div class="notice">{{.Detail.DuplicateNote}}</div>
    <div class="duplicates">
      {{range $i, $path := .Detail.Files}}
        {{if selectedDup $.Detail.SelectedDup $i}}
          <strong>{{add $i 1}}</strong>
        {{else}}
          <a href="{{messageURL $.Detail.Summary.ID $i}}">{{add $i 1}}</a>
        {{end}}
      {{end}}
    </div>
    {{end}}
    {{if .Detail.Attachments}}
    <div class="attachments"><strong>Attachments:</strong> {{range .Detail.Attachments}}<span>{{.}}</span>{{end}}</div>
    {{end}}
  </header>
  <section class="message-body">
    {{if eq .Detail.BodyKind "html"}}
      <iframe sandbox referrerpolicy="no-referrer" srcdoc="{{.Detail.HTMLSrcdoc}}"></iframe>
    {{else if eq .Detail.BodyKind "plain"}}
      <pre>{{.Detail.PlainBody}}</pre>
    {{else}}
      <div class="notice">No text/plain or text/html body part was returned by notmuch.</div>
    {{end}}
  </section>
</article>
{{end}}
{{template "bottom" .}}
{{end}}

{{define "statusPage"}}
{{template "top" (dictTitle "Status")}}
{{if .Error}}
  <div class="notice bad">{{.Error}}</div>
{{else}}
<section class="status-grid">
  <div class="metric"><span>Messages</span><strong>{{.Status.Counts.Messages}}</strong></div>
  <div class="metric"><span>Files</span><strong>{{.Status.Counts.Files}}</strong></div>
  <div class="metric"><span>mbsync lock</span><strong>{{if .Status.MbsyncLockPresent}}present{{else}}absent{{end}}</strong></div>
</section>
<table class="status-table">
  <tbody>
    <tr><th>notmuch</th><td>{{.Status.NotmuchVersion}}</td></tr>
    <tr><th>Config</th><td class="path">{{.Status.ConfigPath}}</td></tr>
    <tr><th>database.path</th><td class="path">{{.Status.DatabasePath}}</td></tr>
    <tr><th>database.mail_root</th><td class="path">{{.Status.MailRoot}}</td></tr>
    <tr><th>maildir.synchronize_flags</th><td>{{.Status.MaildirSyncFlags}}</td></tr>
    <tr><th>index.decrypt</th><td>{{.Status.IndexDecrypt}}</td></tr>
    <tr><th>new.ignore</th><td class="path">{{.Status.NewIgnore}}</td></tr>
  </tbody>
</table>
<h2>Win11 SSH tunnel</h2>
<pre class="code-block">{{.TunnelHint}}</pre>
<div class="notice">The service is intended to bind to localhost inside antiX. Use the SSH tunnel from Windows instead of binding the private mail browser to the LAN.</div>
{{end}}
{{template "bottom" .}}
{{end}}
`
