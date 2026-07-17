{{/* vim: set filetype=mustache: */}}
{{/*
Expand the name of the chart.
*/}}
{{- define "longhorn.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
*/}}
{{- define "longhorn.fullname" -}}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}


{{- define "longhorn.managerIP" -}}
{{- $fullname := (include "longhorn.fullname" .) -}}
{{- printf "http://%s-backend:9500" $fullname | trunc 63 | trimSuffix "-" -}}
{{- end -}}


{{- define "secret" }}
{{- printf "{\"auths\": {\"%s\": {\"auth\": \"%s\"}}}" .Values.privateRegistry.registryUrl (printf "%s:%s" .Values.privateRegistry.registryUser .Values.privateRegistry.registryPasswd | b64enc) | b64enc }}
{{- end }}

{{- /*
longhorn.labels generates the standard Helm labels.
*/ -}}
{{- define "longhorn.labels" -}}
app.kubernetes.io/name: {{ template "longhorn.name" . }}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version | replace "+" "_" }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion }}
{{- end -}}


{{- define "system_default_registry" -}}
{{- if .Values.global.cattle.systemDefaultRegistry -}}
{{- .Values.global.cattle.systemDefaultRegistry -}}
{{- else -}}
{{- "docker.io" -}}
{{- end -}}
{{- end -}}

{{- define "registry_url" -}}
{{- if .Values.privateRegistry.registryUrl -}}
{{- .Values.privateRegistry.registryUrl -}}
{{- else -}}
{{ include "system_default_registry" . }}
{{- end -}}
{{- end -}}

{{- /*
 define the longhorn release namespace
*/ -}}
{{- define "release_namespace" -}}
{{- if .Values.namespaceOverride -}}
{{- .Values.namespaceOverride -}}
{{- else -}}
{{- .Release.Namespace -}}
{{- end -}}
{{- end -}}

{{- /*
multiTypeSetting helper
Input: any value (string, number, or map)
Output: properly quoted YAML string
*/ -}}
{{- define "longhorn.multiTypeSetting" -}}
  {{- $v := . -}}
  {{- if kindIs "map" $v -}}
    {{- $v | toJson | quote -}}
  {{- else -}}
    {{- $v | quote -}}
  {{- end -}}
{{- end -}}

{{/*
Optional timezone injection for all Longhorn workloads.
When .Values.global.timezone is set, this snippet renders a TZ env var.
*/}}
{{- define "longhorn.timezoneEnv" -}}
{{- if .Values.global.timezone }}
- name: TZ
  value: {{ .Values.global.timezone | quote }}
{{- end }}
{{- end -}}

{{- define "longhorn.normalizePath" -}}
{{- $p := trim . -}}
{{- if eq $p "" -}}
{{- "" -}}
{{- else if eq $p "/" -}}
{{- "/" -}}
{{- else -}}
{{- regexReplaceAll "/+$" $p "" -}}
{{- end -}}
{{- end -}}

{{- define "longhorn.requestedDefaultDataPath" -}}
{{- if not (kindIs "invalid" .Values.defaultSettings.defaultDataPath) -}}
{{- .Values.defaultSettings.defaultDataPath -}}
{{- end -}}
{{- end -}}

{{- define "longhorn.requestedDefaultControlPath" -}}
{{- if not (kindIs "invalid" .Values.defaultSettings.defaultControlPath) -}}
{{- .Values.defaultSettings.defaultControlPath -}}
{{- end -}}
{{- end -}}

{{- define "longhorn.effectiveDefaultDataPath" -}}
{{- $existing := dict -}}
{{- if .Capabilities.APIVersions.Has "longhorn.io/v1beta2/Setting" -}}
{{- $existing = (lookup "longhorn.io/v1beta2" "Setting" (include "release_namespace" .) "default-data-path") | default dict -}}
{{- end -}}
{{- if and $existing $existing.value -}}
{{- $existing.value -}}
{{- else -}}
{{- $requested := trim (include "longhorn.requestedDefaultDataPath" .) -}}
{{- if ne $requested "" -}}
{{- $requested -}}
{{- else -}}
{{- "/var/lib/longhorn/" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{- define "longhorn.effectiveDefaultControlPath" -}}
{{- $namespace := include "release_namespace" . -}}
{{- $existingControl := dict -}}
{{- if .Capabilities.APIVersions.Has "longhorn.io/v1beta2/Setting" -}}
{{- $existingControl = (lookup "longhorn.io/v1beta2" "Setting" $namespace "default-control-path") | default dict -}}
{{- end -}}
{{- if and $existingControl $existingControl.value -}}
{{- $existingControl.value -}}
{{- else -}}
{{- $existingData := dict -}}
{{- if .Capabilities.APIVersions.Has "longhorn.io/v1beta2/Setting" -}}
{{- $existingData = (lookup "longhorn.io/v1beta2" "Setting" $namespace "default-data-path") | default dict -}}
{{- end -}}
{{- if and $existingData $existingData.value -}}
{{- "/var/lib/longhorn/" -}}
{{- else -}}
{{- $requested := trim (include "longhorn.requestedDefaultControlPath" .) -}}
{{- if ne $requested "" -}}
{{- $requested -}}
{{- else -}}
{{- "/var/lib/longhorn/" -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{- define "longhorn.validateInstallTimePathSettings" -}}
{{- $namespace := include "release_namespace" . -}}
{{- $existingData := dict -}}
{{- if .Capabilities.APIVersions.Has "longhorn.io/v1beta2/Setting" -}}
{{- $existingData = (lookup "longhorn.io/v1beta2" "Setting" $namespace "default-data-path") | default dict -}}
{{- end -}}
{{- $existingControl := dict -}}
{{- if .Capabilities.APIVersions.Has "longhorn.io/v1beta2/Setting" -}}
{{- $existingControl = (lookup "longhorn.io/v1beta2" "Setting" $namespace "default-control-path") | default dict -}}
{{- end -}}
{{- $requestedData := include "longhorn.normalizePath" (include "longhorn.requestedDefaultDataPath" .) -}}
{{- $requestedControl := include "longhorn.normalizePath" (include "longhorn.requestedDefaultControlPath" .) -}}
{{- $existingDataValue := include "longhorn.normalizePath" ($existingData.value | default "") -}}
{{- $existingControlValue := include "longhorn.normalizePath" ($existingControl.value | default "") -}}
{{- $legacyControlValue := include "longhorn.normalizePath" "/var/lib/longhorn/" -}}
{{- if and $existingData (ne $requestedData "") (ne $requestedData $existingDataValue) -}}
{{- fail (printf "default-data-path is install-time only and cannot be changed after Longhorn has been initialized (existing: %s, requested: %s)" $existingDataValue $requestedData) -}}
{{- end -}}
{{- if and $existingControl (ne $requestedControl "") (ne $requestedControl $existingControlValue) -}}
{{- fail (printf "default-control-path is install-time only and cannot be changed after Longhorn has been initialized (existing: %s, requested: %s)" $existingControlValue $requestedControl) -}}
{{- end -}}
{{- if and (not $existingControl) $existingData (ne $requestedControl "") (ne $requestedControl $legacyControlValue) -}}
{{- fail (printf "default-control-path is install-time only and cannot be changed after Longhorn has been initialized (existing: %s, requested: %s)" $legacyControlValue $requestedControl) -}}
{{- end -}}
{{- end -}}
