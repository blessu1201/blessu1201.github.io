---
layout: article
title: ShellScript(8) - String
tags: [Linux, ShellScript]
key: 20200728_shell_script_08
---

{% include googlead.html %}

---

> `String` (문자열)에 관한 내용입니다.

<br>

## 예제.1 - Combine String variables

{% highlight bash linenos %}
#!/bin/bash

string1="Linux"
string2="Hint"
    echo "$string1$string2"
string3=$string1+$string2
string3+=" is a good tutorial blog site"
    echo $string3
{% endhighlight %}

{% highlight result %}
LinuxHint
Linux+Hint is a good tutorial blog site
{% endhighlight %}

<br>

## 예제.2 - Get substring of String

{% highlight bash linenos %}
#!/bin/bash
Str="Learn Linux from LinuxHint"
subStr=${Str:6:5}
    echo $subStr
{% endhighlight %}

{% highlight result %}
Linux
{% endhighlight %}
