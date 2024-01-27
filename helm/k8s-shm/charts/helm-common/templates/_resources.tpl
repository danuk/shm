{{- define "pod_resources" -}}
resources:
{{ pluck ._app .resources | first | default .resources._default | toYaml | indent 2 }}
{{- end }}

