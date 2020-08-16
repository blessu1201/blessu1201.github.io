---
layout: article
title: 리눅스 서버 시간설정하기
tags: [Linux]
---

{% include googlead.html %}

## 리눅스 현재시스템 시간, H/W시간 확인 및 설정하기
***

<br>

#### 1. 시스템 시간 확인

```
# date
```

<br>

#### 2. H/W 시간 확인

```
# hwclock --show
```

<br>

#### 3. 현재 시스템 시간을 타임서버로 부터 동기화

```
# rdate -s time.bora.net
```

>VMware를 사용하거나, 클라우드 VPC에 서버를 두고 사용할 경우 타임서버로 부터 rdate 설정이 안되는 경우가 있습니다. 그럴 경우 아래방법으로 시도해보세요.


```
# sudo ln -sf /usr/share/zoneinfo/Asia/Seoul /etc/localtime
```

<br>

#### 4. 수동으로 시간설정하기

```
# date -s '2020-07-01 18:47:30'
```

<br>

#### 5. 타임서버시간을 H/W clock에 설정하기

```
# rdate -s time.bora.net && /sbin/clock -w
```
