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
{{- "" -}}
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

{{- /*
systemManagedComponentsNodeSelector helper
Input: any value (string, list, or map)
Output: semicolon-separated `key:value` pairs, the format the
`system-managed-components-node-selector` setting validates against.
A map or a list of `key=value` entries (Kubernetes selector syntax) is
normalized; an entry that still has no `:` separator fails at render time
instead of failing the setting sync in longhorn-manager after install.
*/ -}}
{{/*
Normalize defaultSettings.systemManagedComponentsNodeSelector into the
"key1:value1;key2:value2" form the setting validates. Accepts a string, a map,
or a list whose items are strings or single/multi-key maps. A "key=value" entry
is converted only when it holds exactly one "=" and no ":"; label keys and
values can contain neither character, so that never changes the entry's meaning.
Every resulting pair must be a valid label, otherwise rendering fails, so nothing
reaches longhorn-manager that it would ignore or accept as a garbage key.
*/}}
{{/*
Normalize defaultSettings.systemManagedComponentsNodeSelector into the
"key1:value1;key2:value2" form the setting validates. Accepts a string, a map,
or a list whose items are strings or single/multi-key maps. A "key=value" entry
is converted only when it holds exactly one "=" and no ":"; label keys and
values can contain neither character, so that never changes the entry's meaning.
Every resulting pair must be a valid label, otherwise rendering fails with the
entry as the user wrote it, so nothing reaches longhorn-manager that it would
ignore or accept as a garbage key.
*/}}
{{- define "longhorn.systemManagedComponentsNodeSelector" -}}
  {{- $v := . -}}
  {{- $entries := list -}}
  {{- $origins := list -}}
  {{- $items := list -}}
  {{- if kindIs "map" $v -}}{{- $items = list $v -}}
  {{- else if kindIs "slice" $v -}}{{- $items = $v -}}
  {{- else -}}{{- $items = list (toString $v) -}}
  {{- end -}}
  {{- range $item := $items -}}
    {{- if kindIs "map" $item -}}
      {{- range $k := keys $item | sortAlpha -}}
        {{- $entries = append $entries (printf "%s:%v" $k (get $item $k)) -}}
        {{- $origins = append $origins (printf "%v" $item) -}}
      {{- end -}}
    {{- else if kindIs "string" $item -}}
      {{- range $e := splitList ";" $item -}}
        {{- $e = trim $e -}}
        {{- if $e -}}
          {{- $orig := $e -}}
          {{- if and (not (contains ":" $e)) (eq (len (splitList "=" $e)) 2) -}}
            {{- $e = replace "=" ":" $e -}}
          {{- end -}}
          {{- $entries = append $entries $e -}}
          {{- $origins = append $origins $orig -}}
        {{- end -}}
      {{- end -}}
    {{- else -}}
      {{- fail (printf "defaultSettings.systemManagedComponentsNodeSelector entry %v is invalid: list items must be strings or maps" $item) -}}
    {{- end -}}
  {{- end -}}
  {{- range $i, $e := $entries -}}
    {{- if not (regexMatch "^([a-z0-9]([-a-z0-9.]*[a-z0-9])?/)?[A-Za-z0-9]([-A-Za-z0-9_.]*[A-Za-z0-9])?:([A-Za-z0-9]([-A-Za-z0-9_.]*[A-Za-z0-9])?)?$" $e) -}}
      {{- fail (printf "defaultSettings.systemManagedComponentsNodeSelector entry %q is invalid: the setting expects colon-separated label pairs like \"key1:value1;key2:value2\" (a map or a list of key=value entries is also accepted)" (index $origins $i)) -}}
    {{- end -}}
  {{- end -}}
  {{- join ";" $entries -}}
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
