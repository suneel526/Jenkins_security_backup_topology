{{- define "payment-service.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- define "payment-service.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name (include "payment-service.name" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- define "payment-service.selectorLabels" -}}
app.kubernetes.io/name: {{ include "payment-service.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}
