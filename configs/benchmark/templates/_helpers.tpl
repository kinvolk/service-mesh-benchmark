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

{{- define "bookinfoURLs" }}
{{- $count := .Values.wrk2.app.count | int }}
{{- range $i, $e := until $count }}
        - "http://productpage.bookinfo-{{$i}}:9080/"
        - "http://productpage.bookinfo-{{$i}}:9080/"
        - "http://productpage.bookinfo-{{$i}}:9080/productpage?u=test"
        - "http://productpage.bookinfo-{{$i}}:9080/"
        - "http://productpage.bookinfo-{{$i}}:9080/"
        - "http://productpage.bookinfo-{{$i}}:9080/productpage?u=normal"
        - "http://productpage.bookinfo-{{$i}}:9080/"
        - "http://productpage.bookinfo-{{$i}}:9080/"
        - "http://productpage.bookinfo-{{$i}}:9080/"
        - "http://productpage.bookinfo-{{$i}}:9080/productpage?u=test"
        - "http://productpage.bookinfo-{{$i}}:9080/"
        - "http://productpage.bookinfo-{{$i}}:9080/productpage?u=normal"
        - "http://productpage.bookinfo-{{$i}}:9080/"
        - "http://productpage.bookinfo-{{$i}}:9080/"
        - "http://productpage.bookinfo-{{$i}}:9080/"
        - "http://productpage.bookinfo-{{$i}}:9080/"
        - "http://productpage.bookinfo-{{$i}}:9080/productpage?u=test"
        - "http://productpage.bookinfo-{{$i}}:9080/"
        - "http://productpage.bookinfo-{{$i}}:9080/productpage?u=normal"
        - "http://productpage.bookinfo-{{$i}}:9080/"
{{- end -}}
{{ end }}
