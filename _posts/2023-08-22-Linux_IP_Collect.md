---
layout: article
title: 서버관리_01 / Server IP Collector
tags: [Linux Interface IP Collect]
key: 20230822-linux_server_manage_01 
---

{% include googlead.html %}

---

- 출처 : 유닉스 리눅스 쉘스크립트 예제사전_한빛미디어

## 01. 서버 네트워크 인터페이스와 IP 주소 목록 얻기

> 명령어: ifconfig, awk
> 키워드: NIC, IP주소, 네트워크 인터페이스
> 사용처: 서버 NIC와 IP 주소 목록을 표시하고 싶을때


ex) inet addr:10.211.123.123 이렇게 보일때

 ```bash
#!/bin/bash

# ifconfig 명령어로 유효한 인터페이스 표시
# awk 명령어로 인터페이스명과  IP 주소 추출

LANG=C /usr/sbin/ifconfig |\
awk '/^[a-z]/ {print "[" $1 "]"}
/inet / {split($2,arr,":");} {print $2}'
```

ex) inet 10.211.123.123 이렇게 보일때

```bash
#!/bin/bash

LANG=C /usr/sbin/ifconfig |\
awk '/^[a-z]/ {print "[" $1 "]"}
/inet / {print $2}'
```

스크립트 실행 결과
```
[docker0:]
172.17.0.1
[eth0:]
172.25.149.163
[lo:]
127.0.0.1
```

