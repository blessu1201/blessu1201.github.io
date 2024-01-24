---
layout: article
title: 파일처리_07 여러 HTML 파일에서 title 태그만 추출해서 각각 다른 파일로 출력하기
tags: [Linux, ShellScript, basename, sed]
key: 20240115-Linux-file-html
---

- 출처 : 유닉스 리눅스 쉘스크립트 예제사전_한빛미디어

> 명령어: basename, sed  
> 키워드: for문, 파일 목록, HTML 태그, 다른 파일  
> 사용처: 여러 HTML 파일에서 특정 요소만 추출해서 HTML 파일마다 다른 파일로 출력하고 싶을 때



> 실행 예제  

```
$ ls output/
$ ./htmltitle.sh
$ ls output/
about.txt index.txt menu.txt
```

> 스크립트

```bash
#!/bin/sh

# 현재 디렉터리에 있는  .html 파일이 대상

for htmlfile in *.html # ---------------------------------------------------------- 1
do
  # 파일명에서 확장자를 뺀 문자열 취득
  fname=$(basename $htmlfile.html) # ---------------------------------------------- 2

  # <title> 태그 내용을 후방참조\1로 추출, 파일 출력
  sed -n "s/^.*<title>\(.*\)<\/title>.*$/\1/p" $htmlfile > output/${fname}.txt # -- 3
done
```

&nbsp;
&nbsp;

## **해설** 

이 스크립트는 현재 디렉터리 HTML 파일(확장자가 .html)에서 `<title>` 태그를 추출해서 output이라는 디렉터리에 title 요소를 각각 다른 파일로 저장합니다. 예를 들어 index.html의 title 요소는 index.txt, menu.html은 menu.txt에 출력합니다.
 
`1`{:.info}에서 HTML 파일을 순서대로 처리하는 for문을 작성합니다. 셸 스크립트로 디렉터리 안에 있는 파일을 순서대로 처리하려면 **경로명 확장**이 간단한 방법입니다. for문 in뒤에 *.html이라는 패턴을 넣으면 실행 시 다음처럼 경로명 확장이 일어나서 셸 변수 htmlfile을 써서 각 파일을 순서대로 처리할 수 있습니다.

```
for htmlfile in index.html about.html menu.html
do
...
```

이렇듯 경로명 확장 결과를 for문의 목록으로 넘기는 방법은 다양하게 응용됩니다. 각 파일을 .txt로 출력하기 위해 원래 파일명에서 확장자를 변경한 출력용 파일명을 조합합니다. 그 준비 작업으로 `2`{:.info}에서 우선 대상 html 파일의 파일명에서 확장자를 제거한 문자열을 얻기 위해서 **basename 명령어**를 사용합니다. 이 명령어 출력으로 얻는 문자열 뒤에 임의의 확장자를 붙여서 파일명을 만들면 확장자를 바꿔서 출력할 수 있습니다. 이 스크립트에서는 .txt를 사용합니다.
 
`3`{:.info}은 `<title>` 태그 내용을 패턴 매치로 추출해서 파일에 출력하는 처리입니다. 패턴 매치된 부분을 추출하는 방법은 다양하지만 여기에서는 **sed 명령어**의 **-n 옵션**(패턴스페이스를 출력하지 않음)과 **p 플래그**(치환이 발생했을 때만 출력)를 조합해서 후방참조 \1로 `<title>` 태그 내용을 추출합니다.


&nbsp;
&nbsp;

## **주의사항**

- 이 스크립트는 html 파일 존재 확인을 생략했으므로 현재 디렉터리에 html 파일이 하나도 없으면 에러가 발생합니다.

