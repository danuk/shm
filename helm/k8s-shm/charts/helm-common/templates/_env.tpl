
{{- define "env_by_pluck" -}}
{{- $key  := index . 0 -}}
{{- $dict := index . 1 -}}
{{- range $name, $value := $dict }}
- name: {{ $name }}
  value:
{{- if eq (kindOf $value) "map" -}}
{{- printf " %s" (pluck $key $value | first | default $value._default | toString | quote) }}
{{- else -}}
{{- printf " %s" ($value | toString | quote) }}
{{- end -}}
{{- end }}
{{- end -}}

{{- define "env_tpl" -}}
{{- $root := index . 0 -}}
{{- $env := index . 1 -}}
{{- range $item := $env -}}
{{- if $item.value }}
{{- $_ := set $item "value" (tpl $item.value $root) }}
{{- end }}
{{- end -}}
{{- $env | toYaml }}
{{- end -}}

