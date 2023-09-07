---
layout: article
title: Linux Shell Prompt 글자속성 변경 및 색상지정
tags: [Linux, Bash]
key: 20200721_shell_prompt
---

>Linux Shell-Prompt를 자신이 원하는 셋팅을 하여 가독성을 높일 수 있습니다.<br>
>기호에 맞게 바꿔서 사용해보세요.

<br>

## 1. Text Attributes

| ANSI CODE | Meaning |
|:--------:|:--------:|
|0|Normal Characters|
|1|Bold Characters|
|4|Underlined Characters|
|5|Blinking Characters|
|7|Reverse video Characters|

<br>

## 2. [ COLORS 색상표 ]

| Bold off | color | Bold on | color |
|-|-|-|-|
|0;30 |Balck |1;30| Dark Gray|
|0;31 |Red |1;31 |Dark Red|
|0;32 |Green |1;32 |Dark Green|
|0;33 |Brown |1;33 |Yellow|
|0;34 |Blue |1;34 |Dark Blue|
|0;35 |Magenta |1;35 |Dark Magenta|
|0;36 |Cyan |1;30 |Dark Cyan|
|0;37 |Light Gray |1;30 |White|

<br>

## 3. Foreground, Background 색상표

| Color | Foreground | Background |
|:--:|:--:|:--:|
|black | 30 | 40 |
|red | 31 | 41 |
|green | 32 | 42 |
|yellow | 33 | 43 |
|blue | 34 | 44 |
|magenta | 35 | 45 |
|cyan | 36 | 46 |
|white | 37 | 47 |

<br>

## 4. 사용방법

``` bash
echo -e "\033[40;37;7m Hello World\033[0m"
echo -e "\033[33;44m Yellow text on blue background\033[0m"
echo -e "\033[1;33;44m Bold yellow text on blue background\033[0m"
echo -e "\033[1;4;33;44mBold yellow underlined text on blue background\033[0m"
```

{% highlight bash linenos %}
#!/bin/bash
# This script echoes colors and codes

echo -e "\n\033[4;31mLight Colors\033[0m  \t\t\033[1;4;31mDark Colors\033[0m"
echo -e "\e[0;30;47m Black    \e[0m 0;30m \t\e[1;30;40m Dark Gray  \e[0m 1;30m"
echo -e "\e[0;31;47m Red      \e[0m 0;31m \t\e[1;31;40m Dark Red   \e[0m 1;31m"
echo -e "\e[0;32;47m Green    \e[0m 0;32m \t\e[1;32;40m Dark Green \e[0m 1;32m"
echo -e "\e[0;33;47m Brown    \e[0m 0;33m \t\e[1;33;40m Yellow     \e[0m 1;33m"
echo -e "\e[0;34;47m Blue     \e[0m 0;34m \t\e[1;34;40m Dark Blue  \e[0m 1;34m"
echo -e "\e[0;35;47m Magenta  \e[0m 0;35m \t\e[1;35;40m DarkMagenta\e[0m 1;35m"
echo -e "\e[0;36;47m Cyan     \e[0m 0;36m \t\e[1;36;40m Dark Cyan  \e[0m 1;36m"
echo -e "\e[0;37;47m LightGray\e[0m 0;37m \t\e[1;37;40m White      \e[0m 1;37m"
{% endhighlight %}

<br>

## 5. 적용

> `.bash_profile` 파일에 아래와 같이 변수를 지정하여 설정할 수 있습니다.


{% highlight bash linenos %}
# define colors
C_DEFAULT="\[\033[m\]"
C_WHITE="\[\033[1m\]"
C_BLACK="\[\033[30m\]"
C_RED="\[\033[31m\]"
C_GREEN="\[\033[32m\]"
C_YELLOW="\[\033[33m\]"
C_BLUE="\[\033[34m\]"
C_PURPLE="\[\033[35m\]"
C_CYAN="\[\033[36m\]"
C_LIGHTGRAY="\[\033[37m\]"
C_DARKGRAY="\[\033[1;30m\]"
C_LIGHTRED="\[\033[1;31m\]"
C_LIGHTGREEN="\[\033[1;32m\]"
C_LIGHTYELLOW="\[\033[1;33m\]"
C_LIGHTBLUE="\[\033[1;34m\]"
C_LIGHTPURPLE="\[\033[1;35m\]"
C_LIGHTCYAN="\[\033[1;36m\]"
C_BG_BLACK="\[\033[40m\]"
C_BG_RED="\[\033[41m\]"
C_BG_GREEN="\[\033[42m\]"
C_BG_YELLOW="\[\033[43m\]"
C_BG_BLUE="\[\033[44m\]"
C_BG_PURPLE="\[\033[45m\]"
C_BG_CYAN="\[\033[46m\]"
C_BG_LIGHTGRAY="\[\033[47m\]"

export PS1="$C_GREEN\h:$C_CYAN\$PWD$C_DEFAULT\$ "
{% endhighlight %}
