---
layout: article
title: 리눅스 스왑메모리 생성 / Linux make swap memory
tags: [linux, swap]
key: 20230811-linux_swap_memory
---

{% include googlead.html %}

---

> 리눅스에서 Swap 메모리를 설정하는 방법입니다.

## 1. swap memory의 생성

> Swap의 메모리의 어느정도로 설정할지 결정 후
> dd 명령어를 사용하여 아래와 같이 swapfile 을 만들어 줍니다.
 

```bash
Swap 4G 생성시
$ sudo dd if=/dev/zero of=//swapfile bs=1M count=4096 # 방법 1
$ sudo fallocate -l 4GB /swap/swapfile # 방법 2
```

```bash
Swap 2G 생성시
$ sudo dd if=/dev/zero of=/swap/swapfile bs=1M count=2048 #방법 1
$ sudo fallocate -l 2GB /swap/swapfile # 방법 2
```


## 2. swapfile의 권한 변경

> 생성된 swapfile의 파일권한을 변경합니다.

```bash
$ sudo chmod 600 /swapfile
```

## 3. swapfile 활성화

> 아래 명령어를 통해 swapfile을 통한 swap memory를 활성화 합니다.

```bash
$ sudo mkswap /swapfile
$ sudo swapon /swapfile
```

## 4. fstab 등록

> fstab에 등록하는 이유는 재부팅 후에도 swap을 유지하기 위해서 입니다.

```bash
$ cp /etc/fstab /etc/fstab.old # 기존 fstab 백업
$ sudo vi /etc/fstab
/swapfile swap swap defaults 0 0
```
