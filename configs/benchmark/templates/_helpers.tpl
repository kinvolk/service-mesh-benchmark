{{- define "emojivotoURLs" }}
{{- $count := .Values.wrk2.app.count | int }}
{{- range $i, $e := until $count }}
        - "http://web-svc.emojivoto-{{$i}}/leaderboard"
        - "http://web-svc.emojivoto-{{$i}}/api/vote?choice=:nerd_face:"
        - "http://web-svc.emojivoto-{{$i}}/leaderboard"
        - "http://web-svc.emojivoto-{{$i}}/api/vote?choice=:see_no_evil:"
        - "http://web-svc.emojivoto-{{$i}}/leaderboard"
        - "http://web-svc.emojivoto-{{$i}}/api/vote?choice=:nerd_face:"
        - "http://web-svc.emojivoto-{{$i}}/leaderboard"
        - "http://web-svc.emojivoto-{{$i}}/api/vote?choice=:see_no_evil:"
        - "http://web-svc.emojivoto-{{$i}}/leaderboard"
        - "http://web-svc.emojivoto-{{$i}}/api/vote?choice=:nerd_face:"
        - "http://web-svc.emojivoto-{{$i}}/leaderboard"
        - "http://web-svc.emojivoto-{{$i}}/api/vote?choice=:see_no_evil:"
        - "http://web-svc.emojivoto-{{$i}}/leaderboard"
        - "http://web-svc.emojivoto-{{$i}}/api/vote?choice=:nerd_face:"
        - "http://web-svc.emojivoto-{{$i}}/leaderboard"
        - "http://web-svc.emojivoto-{{$i}}/api/vote?choice=:see_no_evil:"
        - "http://web-svc.emojivoto-{{$i}}/leaderboard"
        - "http://web-svc.emojivoto-{{$i}}/api/vote?choice=:nerd_face:"
        - "http://web-svc.emojivoto-{{$i}}/leaderboard"
        - "http://web-svc.emojivoto-{{$i}}/api/vote?choice=:see_no_evil:"
{{- end -}}
{{ end }}
