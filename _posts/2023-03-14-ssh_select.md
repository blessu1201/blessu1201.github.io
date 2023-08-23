---
layout: article
title: select 문을 활용한 ssh 접속 script / ssh connection script using select
tags: [Linux, Select, Ssh, Shellscript, Bash]
key: 20230314-select_to_ssh
---

{% include googlead.html %}

---

<img src='http://drive.google.com/uc?export=view&id=1F1dcZmQvGuLSXP4WzsdDehD1v7LbJXIv' /><br>

> select 문을 활용하면 자주 접속하는 서버의 IP리스트를 만들어 
> 선택하여 접속하는 방법입니다.
> 기본 22 port를 사용하지 않을 경우에는 port 변수를 만들어 사용하시면 됩니다.

> Using the select statement, you can create a list of frequently accessed server IPs and select and access them.
>If you do not use the default 22 port, you can create and use a port variable.

```bash
#!/bin/bash

# 서버리스트(Server List)
SERVER_LIST=(
"Server_Host_Name1 192.168.0.1"
"Server_Host_Name2 192.168.0.2"
"None"
)

# 계정(Account)
ACCOUNT=MyAccount

PS3="Please select your SERVER: "

# 서버리스트 화면에 출력 후 선택하여 SSH 접속
# After printing on the server list screen, select it to connect to SSH
echo "=============================================================="
echo
select server in "${SERVER_LIST[@]}"; do
    case $server in
        "None") echo "not selected. quit"; break;;
        *) echo "$server selected";
           ip=(${server})
           ssh $ACCOUNT@${ip[1]};break;;
    esac
done
echo "=============================================================="
```