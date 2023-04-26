{{/*
Return a soft podAffinity/podAntiAffinity definition
{{ include "common.affinities.pods.soft" (dict "values" .Values.Labels) -}}
*/}}
{{- define "common.affinities.pods.soft" -}}
preferredDuringSchedulingIgnoredDuringExecution:
  - weight: 1
    podAffinityTerm:
      labelSelector:
        matchExpressions:
        {{- range $key, $value := .labels }}
        - key: {{ $key }}
          operator: In
          values:
          - {{ $value }}
        {{- end }}
      topologyKey: kubernetes.io/hostname
{{- end -}}

{{/*
Return a hard podAffinity/podAntiAffinity definition
{{ include "common.affinities.pods.hard" (dict "values" .Values.Labels) -}}
*/}}
{{- define "common.affinities.pods.hard" -}}
requiredDuringSchedulingIgnoredDuringExecution:
  - labelSelector:
      matchExpressions:
      {{- range $key, $value := .labels }}
      - key: {{ $key }}
        operator: In
        values:
        - {{ $value }}
      {{- end }}
    topologyKey: kubernetes.io/hostname
{{- end -}}

{{/*
Return a podAffinity/podAntiAffinity definition
{{ include "common.affinities.pods" (dict "antiAffinitySoft" false "values" .Values.labels) -}}
*/}}
{{- define "common.affinities.pods" -}}
  {{- if .antiAffinitySoft }}
    {{- include "common.affinities.pods.soft" . -}}
  {{- else }}
    {{- include "common.affinities.pods.hard" . -}}
  {{- end -}}
{{- end -}}

