.:{{ .Values.port }} {
  {{- if .Values.debug.enabled }}
  debug
  {{- end }}
  {{- if .Values.dnsChallenge.enabled }}
  template IN ANY {{ required "Delegated domain ('domain') is mandatory " .Values.domain }} {
      match "_acme-challenge[.](.*)[.]{{ include "k8s-gateway.regex" . }}"
      answer "{{ "{{" }} .Name {{ "}}" }} 5 IN CNAME {{ "{{" }}  index .Match 1 {{ "}}" }}.{{ required "DNS01 challenge domain is mandatory " .Values.dnsChallenge.domain }}"
      fallthrough
  }
  {{- end }}
  k8s_gateway {{ required "Delegated domain ('domain') is mandatory " .Values.domain }} {
    apex {{ .Values.apex | default (include "coredns-gateway.fqdn" .) }}
    ttl {{ .Values.ttl }}
  {{- with .Values.secondary }}
    secondary {{ . }}
  {{- end }}
  {{- with .Values.watchedResources }}
    resources {{ join " " . }}
  {{- end }}
  {{- if .Values.fallthrough.enabled }}
    fallthrough {{- range .Values.fallthrough.zones }} {{ . }} {{- end }}
  {{- end }}
  }
{{- range .Values.extraZonePlugins }}
  {{ .name }}{{ with .parameters }} {{ . }}{{ end }}{{ with .configBlock }} { {{ . | nindent 4 }}
  }{{ end }}
{{- end }}
{{- range .Values.zoneFiles }}
  file /etc/coredns/{{ .filename }}{{ if .domains }} {{ .domains }}{{ end }}
{{- end }}
}
