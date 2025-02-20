{{- range $name, $conf := .Values.extraConfig }}
{{ $name }}{{ if $conf.parameters }} {{ $conf.parameters }}{{ end }}
{{- end }}
{{- range (required "Coredns servers are mandatory " .Values.servers) }}
  {{- range $idx, $zone := .zones }}{{ if $idx }} {{ else }}{{ end }}{{ default "" $zone.scheme }}{{ default "." $zone.zone }}{{ else }}.{{ end -}}
    {{- if .port }}:{{ .port }} {{ end -}}
{
        {{- range .plugins }}
  {{ .name }}{{ if .parameters }} {{ .parameters }}{{ end }}{{ if .configBlock }} {
{{ .configBlock | indent 4 }}
  }{{ end }}
        {{- end }}
}
{{- end }}
