---
layout: article
title: 텍스트처리_18 HTML 파일 문자 코드를 자동으로 판별해서 UTF-8로 인코딩된 파일로 바꾸기
tags: [Linux, ShellScript, grep, sed, iconv]
key: 20240229-linux-grep, sed, iconv
---

- 출처 : 유닉스 리눅스 쉘스크립트 예제사전_한빛미디어

> 명령어: grep, sed, iconv  
> 키워드: HTML, meta 태그, 문자 코드  
> 사용처: HTML 파일 meta 태그에서 자동으로 문자 코드를 판별해서 UTF-8로 변환하고 싶을 때

--- 

> 실행예제

```
$ ./charset-utf8.sh
$ ls newdir/     <------ 디렉터리 newdir에 작성한 html 파일이 저장되었는지 확인
index.html euckr.html
```

> 스크립트

```bash
#!/bin/sh

# 변환한 파일을 출력할 디렉터리
outdir="newdir"  #---------------------------------------------------- 1

# 파일 출력용 디렉터리 확인
if [ ! -d "$outdir" ]; then  #---------------------------------------- 2(if문)
  echo "Not a directory: $outdir"
  exit 1
fi

# 현재 디렉터리의 .html 파일이 대상
for filename in *.html  #--------------------------------------------- 3
do
  # grep 명령어로 meta태그 Content-Type을 선택해서
  # sed 명령어로 charset=지정 부분 추출
  charset=$(grep -i '<meta ' "$filename" |\  #------------------------ 4
  grep -i 'http-equiv="Content-Type"' |\
  sed -n 's/.*charset=\([-_a-zA-Z0-9]*\)".*/\1/p')

  # charset을 얻지 못하면 iconv 명령어를 실행하지 않고 건너뛰기
  if [ -z "$charset" ]; then  #--------------------------------------- 5
    echo "charset not found: $filename" >&2
    continue
  fi

  # meta 태그에서 추출한 문자 코드에서 UTF-8으로 변환
  # 디렉터리 $outdir에 출력
  iconv -c -f "$charset" -t UTF-8 "$filename" > "${outdir}/${filename}"  #-- 6
done


```

&nbsp;
&nbsp;
                                                
## **해설**

이 스크립트는 현재 디렉터리에 있는 HTML 파일(확장자 .html)을 HTML 파일에 있는 meta 태그로 지정한 문자 인코딩을 써서 UTF-8로 변환합니다. 다양한 문자 코드로된 HTML 파일을 UTF-8로 일괄 변환할 때 사용하면 됩니다 변환에는 문자 코드를 바꿀때 다주 사용하는 **iconv 명령어**를 사용합니다.

`1`{:.info}에서 우선 변환 후 출력할 디렉터리를 정의합니다. 여러 html 파일을 처리해서 셸 변수 outdir로 정의한 디렉터리에 출력합니다.

`2`{:.info}는 이 출력용 디렉터리를 확인합니다. 디렉터리인지 확인하는 **-d** 연산자와 부정 연산자 !를 써서 출력용 디렉터리가 존재하지 않거나 디렉터리가 아니라면 에러를 표시하고 종료합니다.

`3`{:.info}에서 for문 in에 *.html을 지정해서 현재 디렉터리에 있는 HTML 파일을 순서대로 셸 변수 filename에 넣어 처리합니다. for문 안 `4`{:.info}에서는 HTML 파일에서 문자 코드를 추출하고 셸 변수 charset에 저장합니다. 그리고 각 명령어를 파이프로 연결하면 길어지므로 줄 끝에 \ 기호를 써서 줄바꿈을 합니다.

HTML charset 지정을 알아봅시다. HTML은 파일 **문자 코드**를 meta 태그 content 속성에서 **charset=** 으로 지정합니다.

- HTML 파일로 문자 코드 지정 예

  - EUC-KR 지정  

  ```
  <meta http-equiv="Content-Type" content="text/html; charset=euc-kr">
  ```

  - content 속성과 http-equiv 속성 순서는 바뀌어도 됨  

  ```
  <meta content="text/html; charset=utf-8" http-equiv="Content-Type">
  ```

  - 태그를 대문자로 쓰거나 charset 앞에 공백이 없을 수도 있음  

  ```
  <META HTTP-EQUIV="Content-Type" CONTENT="text/html;charset="UTF-8">
  ```


이렇듯 HTML 표기 방법은 다양하므로 전부 대응하는건 힘듭니다. 이 스크립트는 `4`{:.info}에서 다음과 같은 사양으로 문자 코드 지정을 추출합니다.

1. `<meta와 http-qequiv="Content-Type"`{:.success}를 포함한 줄을 grep으로 선택
2. charset= 문자열 뒤에 딸린 문자열을 sed 명령어로 추출

`4`{:.info}에서 명령어군 전체를 **명령어 치환$()**로 싸서 셸 변수 charset에 대입합니다. 두 **grep 명령어**는 **-i 옵션**으로 대소문자 구분없이 실행합니다. 이것은 태그는 대문자로 작성할 수도 있기 때문입니다.

`4`{:.info}마지막 파이프 처리에 있는 **sed 명령어**는 charset=xxxx에서 xxxx 문자열을 추출하는 처리입니다. 여기서 charset 등호 기호 뒤에 추출할 문자 코드가 들어 있으므로 이걸 charset=\([-_a-zA-Z0-9]*\) 라는 패턴을 지정합니다. 문자 코드는 EUC-KR처럼 기본적으로 알파벳, 하이픈, 언더바, 숫자로만 구성되므로 이걸 문자 클래스로 [-_a-zA-Z0-9] 처럼 표현합니다.

<img src='http://drive.google.com/thumbnail?id=15mmkTJ6Xgvh2YBS-F7PqV_oATHpdO25F&sz=w1000' /><br>

이때 하이픈은 범위 지정에서도 사용하므로 문자 클래스에서 하이픈 그 자체를 지정할 때는 제일 처음 또는 마지막에 적어야 합니다.

sed 명령어 일치 부분으로 charset= 뒤를 \(\)로 싼 것은 **후방참조**(일치 부분 추출)를 위해서 입니다. sed 명령어에서 패턴 스페이스를 출력하지 않는 **-n 옵션**을 쓰고 치환 후 문자열 후방참조 **\1**로 하고, p 플래그를 보태서 출력한 뒤 일치한 부분만 추출합니다.

`3`{:.info}는 `4`{:.info}에서 추출한 charset 문자열을 확인합니다. charset 지정이 없는 HTML 파일이거나 문자 코드를 판별하지 못했으면 셸 변수 charset에 빈 문자열이 들어갑니다. 따라서 `5`{:.info}에서 **test 명령어**로 빈 문자열인가 확인하는 **-z 연산자**를 사용해 셸 변수 charset을 확인하는데, 만약 참이면 continue문으로 건너뜁니다.

`4`{:.info}에서 셸 변수 charset에 문자 코드가 대입되므로 이걸 iconv 명령어로 처리합니다`6`{:.info}.  
iconv 명령어 사용법은 다음과 같습니다.

```
iconv -f <입력 문자 코드> -t <출력 문자 코드> <파일명>
```

입력 문자 코드는 `4`{:.info}에서 추출했으므로 이걸 -f 옵션에 지정합니다. 출력 문자 코드는 UTF-8로 지정합니다. `6`{:.info}은 지정한 문자 코드가 처리 안 되는 문자라면 무시하는 -c 옵션을 추가합니다. -c 지정이 없으면 한 문자라도 처리 못하는 글자가 들어 있으면 에러가 발생해서 멈추게 되므로 이 옵션이 있는 편이 낫습니다.

`6`{:.info}마지막에 출력을 newdir 디렉터리로 리다이렉트해서 변환한 파일을 출력합니다. 이렇게 해서 일괄적으로 HTML 파일을 UTF-8로 출력할 수 있습니다.

그리고 HTML 파일은 역사가 길고 여러 문법이 있으므로 이런 스크립트에서 제대로 처리하지 못하는 파일이 있을 수도 있습니다.

&nbsp;
&nbsp;

## **주의사항**

- 이 스크립트는 charset 지정이 없는 HTML 파일을 변환하지 못합니다. 그리고 출력된 파일은 meta 태그에 뭐가 지정되더라도 UTF-8 파일이 됩니다.

- HTML5는 다음처럼 간단한 charset 지정이 가능합니다.

  ```
  <mete charset="UTF-8">
  ```

  예제에서는 이 형식에 대응하지 못하므로 sed 명령어 부분을 다음처럼 변경해야 합니다.

  ```
  sed -n 's/<meta .*charset=" \([-_a-zA-z0-9]*\)" .*/\1/p'
  ```

- HTML 문자 코드 중에는 x-으로 시작하는게 있는데 iconv 명령어에서 처리하지 못하는 코드가 있어서 에러를 발생하기도 합니다.
