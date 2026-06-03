{{/*
Expand the chart name.
*/}}
{{- define "gitflow-analyzer.name" -}}
{{- .Chart.Name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Full release name, capped at 63 chars (Kubernetes DNS label limit).
*/}}
{{- define "gitflow-analyzer.fullname" -}}
{{- $name := .Chart.Name }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}

{{/*
Chart label — name + version, used on all managed resources.
*/}}
{{- define "gitflow-analyzer.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels applied to every resource.
*/}}
{{- define "gitflow-analyzer.labels" -}}
helm.sh/chart: {{ include "gitflow-analyzer.chart" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
ServiceAccount name. Uses the value from values.yaml.
*/}}
{{- define "gitflow-analyzer.serviceAccountName" -}}
{{ .Values.serviceAccount.name }}
{{- end }}
