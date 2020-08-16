---
layout: article
title: Markdown Syntax
tags: [Markdown]
---

{% include googlead.html %}

# Markdown 문법정리
>Markdown의 문법을 정리합니다.

<br>
H1 ~ H6 까지 표현가능, #의 개수로 표현합니다.

*Markdown*
```
# H1
## H2
### H3
#### H4
##### H5
###### H6
```

# H1
## H2
### H3
#### H4
##### H5
###### H6

```
제목1
=====

제목2
-----
```

제목1
=====

제목2
-----

<br>

#### 2. 인용

```
> This is a first blockqute.
>> This is a second blockqute.
>>> This is a third blockqute.
```

> This is a first blockqute.
>> This is a second blockqute.
>>> This is a third blockqute.

<br>

#### 3.정렬

 *순서형, 비순서형*

```
Unordered
* Item 1
* Item 2
    * Item 2a
    * Item 2b

Ordered
1. Item 1
1. Item 2
1. Item 3
    1. Item 3a
    1. Item 3b
```

Unordered
* Item 1
* Item 2
    * Item 2a
    * Item 2b

Ordered
1. Item 1
1. Item 2
1. Item 3
    1. Item 3a
    1. Item 3b

<br>

#### 4.코드블록

<pre>
```
function test() {
 console.log("hello world!");
}
```
</pre>

```javascript
function test() {
 console.log("hello world!");
}
```

<br>
#### 5. 강조

```
이텔릭체는 *별표(asterisks)* 혹은 _언더바(underscore)_를 사용하세요.
두껍게는 **별표(asterisks)** 혹은 __언더바(underscore)__를 사용하세요.
**_이텔릭체_와 두껍게**를 같이 사용할 수 있습니다.
취소선은 ~~물결표시(tilde)~~를 사용하세요.
<u>밑줄</u>은 `<u></u>`를 사용하세요.
```
이텔릭체는 *별표(asterisks)* 혹은 _언더바(underscore)_를 사용하세요.
두껍게는 **별표(asterisks)** 혹은 __언더바(underscore)__를 사용하세요.
**_이텔릭체_와 두껍게**를 같이 사용할 수 있습니다.
취소선은 ~~물결표시(tilde)~~ 를 사용하세요.
<u>밑줄</u>은 `<u></u>` 를 사용하세요._

<br>
#### 6. 테이블

```
|제목|내용|설명|
|:---|---:|:---:|
|왼쪽정렬|오른쪽정렬|중앙정렬|
|왼쪽정렬|오른쪽정렬|중앙정렬|
|왼쪽정렬|오른쪽정렬|중앙정렬|
```

|제목|내용|설명|
|:---|---:|:---:|
|왼쪽정렬|오른쪽정렬|중앙정렬|
|왼쪽정렬|오른쪽정렬|중앙정렬|
|왼쪽정렬|오른쪽정렬|중앙정렬|

테이블 위아래로 공백이 있어야 제대로 나옵니다.

<br>
#### 7. 인라인 코드블록

<pre>
`인라인 코드 블록`
</pre>

`인라인 코드 블록`

<br>
#### 8. 링크

```
[GOOGLE](https://google.com)

[NAVER](https://naver.com "링크 설명(title)을 작성하세요.")

[상대적 참조](../users/login)

[Dribbble][Dribbble link]

[GitHub][1]

문서 안에서 [참조 링크]를 그대로 사용할 수도 있습니다.

다음과 같이 문서 내 일반 URL이나 꺾쇠 괄호(`< >`, Angle Brackets)안의 URL은 자동으로 링크를 사용합니다.
구글 홈페이지: https://google.com
네이버 홈페이지: <https://naver.com>

[Dribbble link]: https://dribbble.com
[1]: https://github.com
[참조 링크]: https://naver.com "네이버로 이동합니다!"
```

[GOOGLE](https://google.com)

[NAVER](https://naver.com "링크 설명(title)을 작성하세요.")

[상대적 참조](../users/login)

[Dribbble][Dribbble link]

[GitHub][1]

문서 안에서 [참조 링크]를 그대로 사용할 수도 있습니다.  

다음과 같이 문서 내 일반 URL이나 꺾쇠 괄호(`< >`, Angle Brackets)안의 URL은 자동으로 링크를 사용합니다.
구글 홈페이지: https://google.com
네이버 홈페이지: <https://naver.com>

[Dribbble link]: https://dribbble.com
[1]: https://github.com
[참조 링크]: https://naver.com "네이버로 이동합니다!"
