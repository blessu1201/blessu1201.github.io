---
layout: article
title: 리눅스 openssl을 활용한 파일 암,복호화 / Linux using openssl for file encryption
tags: [Linux, Openssl]
key: 20230809-linux_openssl_file_encrypt
---

> 리눅스 사용시 로그파일의 크기가 증가하거나 갯수가 증가하게 되면, 로그를 주기적으로 삭제해 줘야 합니다.
> 하지만 로그의 보관주기를 생각하면 일정기간 로그파일을 남겨둬야 하고, 시간이 어느정도 흐른 후
> 과거 로그파일을 들춰봐야 하는 경우가 발생합니다. 로그에는 민감한 정보가 남는 경우도 발생하기 때문에
> 보안적 측면에서 로그파일을 담당자만 열람 할 수 없게 openssl을 이용하여 파일을 암호화하는 방법에 대해 알아보도록 하겠습니다.


## 1. openssl 을 이용하여 파일 암호화

> 암호화(aes-256-cbc)

```bash
openssl aes-256-cbc -in my_file.txt -out my_file.enc
```

## 2. openssl 을 이용하여 파일 복호화

> 복호화(aes-256-cbc)

```bash
openssl aes-256-cbc -d -in my_file.txt -out my_file.enc
```

## 3. 비밀번호를 사용한 파일 암호화

> 비밀번호를 사용하여 암호화

```bash
openssl aes-256-cbc -salt -k password -in myfile.txt -out myfile.enc
```

## 4. 비밀번호가 설정된 파일의 복호화

> 비밀번호를 사용한 복호화

```bash
openssl aes-256-cbc -d -salt -in myfile.txt.enc -out myfile.txt -k password

```

> 1개의 파일보다도 일별 로그파일이 여러개일 경우 디렉토리를 tar로 먼저 묶어 파일로 만든 후
> 암호화 처리하면 됩니다. script를 작성하여 crontab에 등록하여 자동화 하면
> 로그파일을 좀 더 수월하게 관리가 가능합니다.
