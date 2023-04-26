{{/*
Expand the name of the chart.
*/}}
{{- define "helm.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "helm.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "helm.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "helm.labels" -}}
helm.sh/chart: {{ include "helm.chart" . }}
{{ include "helm.selectorLabels" . | fromJson | toYaml }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "helm.selectorLabels" -}}
{{- dict "app.kubernetes.io/name" (include "helm.name" .) "app.kubernetes.io/instance" .Release.Name | toJson }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "helm.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "helm.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}


{{/*
Usage example:
  var_by_tier: {{ include "var_by_pluck" (list $.Values.global.tier .var) | default true }}
  var_by_br:   {{ include "var_by_pluck" (list $.Values.global.git_branch .var) }}
*/}}
{{- define "var_by_pluck" -}}
{{- $key  := index . 0 -}}
{{- $dict := index . 1 -}}
{{- if eq (kindOf $dict) "map" -}}
  {{- $var := pluck $key $dict | first }}
  {{- if eq (kindOf $var) "bool" -}}
    {{- $var }}
  {{- else -}}
    {{- $var := default $dict._default $var }}
    {{- if eq (kindOf $var) "map" -}}
      {{- $var | toJson }}
    {{- else -}}
      {{- if eq (kindOf $var) "bool" -}}
        {{- $var }}
      {{- else -}}
        {{- $var | default "" }}
      {{- end -}}
    {{- end -}}
  {{- end -}}
{{- else -}}
  {{- if eq (kindOf $dict) "bool" -}}
    {{- $dict }}
  {{- else -}}
    {{- $dict | default "" }}
  {{- end -}}
{{- end -}}
{{- end -}}

{{- define "should_be_deployed" -}}
{{- $ := index . 0 -}}
{{- $item := index . 1 -}}
{{- if or $item.deploy_only_for_tiers $item.deploy_only_for_branches -}}
  {{- if has $.Values.global.tier $item.deploy_only_for_tiers -}}
  {{- "yes" -}}
  {{- else if has $.Values.global.git_branch $item.deploy_only_for_branches -}}
  {{- "yes" -}}
  {{- end -}}
{{- else -}}
{{- "yes" -}}
{{- end -}}
{{- end -}}

{{ define "imagePullSecrets" }}
{{- $global_regcred := (index . 0).Values.global.imagePullSecrets | default list }}
{{- $local_regcred := index . 1 | default list }}
{{- if $regcred := concat $global_regcred $local_regcred | compact | uniq }}
{{- with $regcred }}
imagePullSecrets:
  {{- toYaml . | replace " - " " " | nindent 2 }}
{{- end }}
{{- end }}
{{ end }}

{{- define "tolerations" -}}
tolerations:
{{- range ._tolerations }}
  - effect: {{ .effect | default "NoSchedule" }}
    operator: {{ .operator | default "Equal" }}
    {{- if and .key .value }}
    key: {{ .key }}
    value: {{ .value }}
    {{- end }}
{{- end -}}
{{- end -}}
