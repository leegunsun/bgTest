tch-deployment.sh` 같은 스크립트는 NGINX가 “공식으로 배포”하는 표준 도구가 아닙니다.**
  NGINX가 권장/공식으로 제공하는 것은 “구성 변경 → 구문 검사(nginx -t) → **무중단 리로드(HUP 신호)**”라는 운영 방식입니다. 리로드 시 새 워커가 새 설정으로 뜨고, 기존 워커는 기존 연결을 **우아하게(gracefully)** 종료합니다. 이것이 무중단 전환의 핵심 메커니즘입니다. ([nginx.org][1], [NGINX Documentation][2])

* 즉, **스크립트의 존재 자체는 문제 아님**. 다만 “무엇을 어떻게 바꾸고 리로드하느냐”가 중요합니다. 아래의 베스트 프랙티스대로 구현되어 있으면, 스크립트를 써도 **공식 메커니즘을 정확히 따르는 것**이 됩니다.

---

# 검증 포인트 (당신의 방식이 공식 메커니즘을 따르는지)

1. **트래픽 전환을 “설정값”으로 제어**하고 있는가

   * 보통은 `upstream`에 `blue`, `green` 두 그룹을 정의하고, `proxy_pass` 대상은 **변수**를 사용해 런타임에 바꿉니다. NGINX는 `proxy_pass`에 **변수**를 허용하고(변수 값이 도메인/그룹이면 그 그룹을 찾아 라우팅), `upstream` 그룹도 공식 모듈로 지원합니다. ([nginx.org][3])

2. **리로드가 “무중단(reload/HUP)”으로 실행되는가**

   * `nginx -t && nginx -s reload` 또는 `systemctl reload nginx`를 이용해 **리로드**만 수행해야 합니다. 이때 **새 워커가 뜨고, 기존 워커는 우아 종료**합니다. 이것이 공식 동작입니다. ([nginx.org][1], [NGINX Documentation][2])

3. **건강상태(health) 확인 절차가 있는가**

   * 오픈소스 NGINX는 **능동(Active) 헬스체크가 내장되어 있지 않고** 수동(패시브)만 됩니다. 능동 헬스체크를 NGINX 레벨에서 쓰려면 **NGINX Plus**가 필요합니다. 스크립트에서 `/health`를 `curl`로 사전 확인하는 방식은 합리적입니다. ([NGINX Documentation][4])

4. **롤백이 즉시 가능한가**

   * 실패 시 반대편(`blue`↔`green`)으로 설정을 되돌리고 다시 `nginx -s reload`로 원복되어야 합니다. 이 또한 공식 리로드 메커니즘을 따릅니다. ([nginx.org][1])

---

# 올바른(권장) 구성 예시

아래 예시는 “스크립트가 설정 한 줄만 바꾸고, 리로드만 수행”하도록 설계합니다.
구성의 핵심은 **include 파일 또는 map 변수**로 활성 색상을 바꾸는 것입니다.

### 1) NGINX 설정

```nginx
# /etc/nginx/conf.d/upstreams.conf
upstream blue {
    server 127.0.0.1:8081;
}
upstream green {
    server 127.0.0.1:8082;
}
```

```nginx
# /etc/nginx/conf.d/active.env
# 초기값: blue 또는 green 중 하나
set $active "blue";
```

```nginx
# /etc/nginx/conf.d/routing.conf
map $active $backend {
    default   blue;
    blue      blue;
    green     green;
}
```

([nginx.org][1])

```nginx
# /etc/nginx/nginx.conf (또는 server 블록 내부)
http {
    include /etc/nginx/conf.d/upstreams.conf;
    include /etc/nginx/conf.d/routing.conf;

    server {
        listen 80;
        # active.env는 server 또는 http 블록에서 include 가능
        include /etc/nginx/conf.d/active.env;

        location /health {
            return 200 "ok\n";
        }

        location / {
            # 변수 기반 proxy_pass: 변수 값이 'blue'/'green'이면 해당 upstream 그룹을 찾아 라우팅
            proxy_pass http://$backend;
            proxy_http_version 1.1;
            proxy_set_header Host $host;
            proxy_set_header Connection "";
        }
    }
}
```

* `proxy_pass`에 **변수 사용**은 문서상 허용되며, 변수 값이 도메인/그룹일 때 해당 서버 그룹을 찾습니다.
* `upstream` 그룹 정의는 공식 모듈(`ngx_http_upstream_module`)의 표준 방법입니다. ([nginx.org][3])
* `map`은 런타임 변수 매핑에 쓰는 공식 디렉티브입니다. ([nginx.org][1])

### 2) 전환 스크립트(안전한 샘플)

```bash
#!/usr/bin/env bash
# /usr/local/bin/switch-deployment.sh

set -euo pipefail

ACTIVE_FILE="/etc/nginx/conf.d/active.env"
NEW="$1"   # "blue" 또는 "green"

if [[ "$NEW" != "blue" && "$NEW" != "green" ]]; then
  echo "Usage: $0 {blue|green}" >&2
  exit 2
fi

# 대상 포트/엔드포인트 매핑(운영 환경에 맞게 조정)
probe_url="http://127.0.0.1:8081/health"
[[ "$NEW" == "green" ]] && probe_url="http://127.0.0.1:8082/health"

echo "[1/4] 프로브 체크: $probe_url"
curl -fsS --max-time 2 "$probe_url" >/dev/null

echo "[2/4] active.env 갱신"
tmp=$(mktemp)
echo "set \$active \"$NEW\";" > "$tmp"
# 원자적 교체
install -o root -g root -m 0644 "$tmp" "$ACTIVE_FILE"
rm -f "$tmp"

echo "[3/4] NGINX 설정 검사"
nginx -t

echo "[4/4] 무중단 리로드(HUP)"
nginx -s reload

echo "완료: 현재 활성 색상 => $NEW"
```

* 핵심은 \*\*(a) 새 버전 상태 확인 → (b) 설정 한 줄 갱신 → (c) `nginx -t` → (d) `nginx -s reload`\*\*의 순서를 지키는 것입니다. 리로드(HUP)는 **새 워커 생성 + 기존 워커 우아 종료**를 보장합니다. ([nginx.org][1], [NGINX Documentation][2])

> systemd를 쓰면 `nginx -t && systemctl reload nginx`도 동일한 효과입니다. ([NGINX Documentation][2])

---

# 점진적 전환(카나리)도 필요하다면

배포 리스크를 더 줄이고 싶다면 **일부 트래픽만 green으로 보내는 카나리**를 고려하세요. `split_clients`로 간단히 구현할 수 있습니다.

```nginx
split_clients "$remote_addr$request_id" $bucket {
    5%     "canary";
    *      "stable";
}

map $bucket $backend {
    canary  green;
    stable  blue;
}
```

* `split_clients`는 해시 기반으로 트래픽 비율을 나누는 공식 디렉티브입니다. 비율만 바꾼 뒤 리로드하면 됩니다. ([NGINX Documentation][5])

---

# NGINX Open Source vs. NGINX Plus (참고)

* **Open Source NGINX**: 위에서 설명한 **리로드 기반 전환**이 표준입니다. 능동 헬스체크는 없고(수동만), API로 동적 업스트림 변경도 없습니다. 스크립트로 헬스 프로브 후 리로드하는 지금의 접근이 맞습니다. ([NGINX Documentation][4])
* **NGINX Plus**:

  * **능동(Active) 헬스체크**를 NGINX 내장으로 설정 가능. ([NGINX Documentation][4])
  * \*\*REST API(ngx\_http\_api\_module)\*\*로 업스트림을 동적으로 추가/제거/가중치 조절 가능(리로드 불필요). 대규모 자동화나 오토스케일 환경에 적합합니다. ([NGINX Documentation][6], [nginx.org][7])

---

# 운영 체크리스트

1. **구성 테스트 필수**: 항상 `nginx -t`로 문법 검증 후 리로드. (자동화 스크립트에 `&&`로 연결) ([Stack Overflow][8])
2. **원자적 파일 교체**: 전환 변수 파일(`active.env`)은 `mktemp` + `install`로 원자 교체(부분 기록 방지).
3. **헬스프로브 타임아웃**: `curl --max-time`으로 지연 전파 방지.
4. **접속 드레이닝**: 리로드는 워커 드레이닝을 자동 수행(기존 연결은 기존 워커가 끝까지 처리). 웹소켓 등 장기 연결이 매우 오래 남을 수 있으니, 필요 시 애플리케이션 레벨 타임아웃을 설계하세요. ([nginx.org][1], [Stack Overflow][9])
5. **롤백 경로**: 실패 시 즉시 반대 색상으로 되돌리고 재리로드.
6. **로깅/모니터링**: 상태/오류 로그에서 전환 직후 5\~10분 집중 모니터링.

---

# 결론

* **NGINX가 제공하는 “공식 전환 도구”는 없습니다.** 그러나 “설정 기반 전환 + 무중단 리로드(HUP)”는 **공식 동작 방식**이며, 이를 자동화하는 스크립트(`switch-deployment.sh`)는 **정석적인 구현**입니다.
* 위 샘플처럼 **upstream + map 변수 + include 파일 + 리로드** 조합으로 구성하고, **헬스체크 → 설정 교체 → 구문 검사 → 리로드** 순서를 지키면 신뢰성 높게 블루/그린을 운영할 수 있습니다. ([nginx.org][1], [NGINX Documentation][2])

---

**Q1**: 지금 환경에서 헬스체크는 어디에서 수행하고 있나요? 앱 레벨 `/health` 경로의 스펙(응답 코드/본문/의존성 체크 범위)을 알려주면 더 견고한 전환 조건을 설계해줄 수 있어요.
**Q2**: 장기 연결(웹소켓, SSE)이 있나요? 있다면 리로드 후 드레이닝 정책(최대 유지 시간, 강제 종료 시점)을 함께 정리해드릴게요. ([Stack Overflow][9])
**Q3**: 카나리(예: 5% → 25% → 100%) 단계적 전환을 원하나요? 원한다면 `split_clients` 기반의 구체적 구성과 스크립트까지 맞춰 드릴게요. ([NGINX Documentation][5])

[1]: https://nginx.org/en/docs/control.html?utm_source=chatgpt.com "Controlling nginx"
[2]: https://docs.nginx.com/nginx/admin-guide/basic-functionality/runtime-control/?utm_source=chatgpt.com "Control NGINX Processes at Runtime"
[3]: https://nginx.org/en/docs/http/ngx_http_upstream_module.html?utm_source=chatgpt.com "Module ngx_http_upstream_module - nginx"
[4]: https://docs.nginx.com/nginx/admin-guide/load-balancer/http-health-check/?utm_source=chatgpt.com "HTTP Health Checks | NGINX Documentation"
[5]: https://docs.nginx.com/nginx/admin-guide/load-balancer/tcp-health-check/?utm_source=chatgpt.com "TCP Health Checks | NGINX Documentation"
[6]: https://docs.nginx.com/nginx/admin-guide/load-balancer/dynamic-configuration-api/?utm_source=chatgpt.com "Dynamic Configuration of Upstreams with the NGINX Plus API"
[7]: https://nginx.org/en/docs/http/ngx_http_api_module.html?utm_source=chatgpt.com "Module ngx_http_api_module - nginx"
[8]: https://stackoverflow.com/questions/18587638/how-do-i-restart-nginx-only-after-the-configuration-test-was-successful-on-ubunt?utm_source=chatgpt.com "How do I restart nginx only after the configuration test was ..."
[9]: https://stackoverflow.com/questions/32496799/nginx-ungraceful-worker-termination-after-timeout?utm_source=chatgpt.com "nginx - ungraceful worker termination after timeout - Stack Overflow"

