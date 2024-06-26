---
layout: article
title: 파일처리_01 절대 경로, 상대 경로 관계없이 같은 동작하기(cd, dirname)
tags: [Linux, ShellScript, cd, dirname]
key: 20240110-Processing Linux files
---

- 출처 : 유닉스 리눅스 쉘스크립트 예제사전_한빛미디어

> 명령어: cd, dirname   
> 키워드: 절대 경로, 상대 경로, 전체 경로, cron  
> 사용처: cron 동에서 스크립트를 전체 경로로 실행할 때 상대 경로로 실행한 것과 같은 동작을 하고 싶을 때  

> 실행 예제  

```
$ cd /home/user1
$ /home/user1/myapp/dirname.sh
START
END
```

> 스크립트

```bash
#!/bin/sh
 
cd "$(dirname "$0")" #---- 1
 
./start.sh
./end.sh
```

&nbsp;
&nbsp;

## **해설** 

이 스크립트는 두 외부 파일 start.sh와 end.sh를 순서대로 실행합니다. 여기서 start.sh와 end.sh 두 파일은 /home/user1/myapp 디렉터리에 설치되어 있고 각 파일의 내용은 "START", "END"입니다.
 
그런데 셸 스크립트 내부에서 다른 셸 스크립트를 실행할 때는 경로에 주의해야 합니다. 그렇지 않으면 아래 예제처럼 만들지도 모릅니다.

- `파일1`{:.success} 현재 디렉터리가 어디인지 고려 없이 사용한 예

    ```
    #!/bin/sh

    ./start.sh
    ./end.sh
    ```

스크립트를 작성할 때는 셸 스크립트 파일이 저장된 디렉터리를 현재 디렉터리로 작업하는 일이 많으므로 위의 스크립트는 정상적으로 동작합니다. 하지만 스크립트를 완성해서 cron에 등록해서 정기적으로 실행한다면 이 스크립트는 다음처럼 에러를 발생할지도 모릅니다.

- cron등록 실행결과

    ```
    /home/user1/myapp/dirname.sh: line 3: ./start.sh: No such file or directory
    /home/user1/myapp/dirname.sh: line 4: ./end.sh: No such file or directory
    ```

이처럼 직접 실행할 땐 정상이었지만 cron에 등록해서 배치 처리할 때 제대로 동작하지 않는 상황은 심심치 않게 벌어집니다. 이것은 cron 실행 시 현재 디렉터리가 **cron 실행 사용자의 홈 디렉터리**가 되기 때문입니다. 

즉, cron에서 dirname.sh가 실행되면 현재 디렉터리는 /home/user1 로 되어 여기서 ./start.sh를 지정하면 /home/user1/start.sh 파일을 찾게 됩니다. 스크립트 내부에서 다른 셸 스크립트를 실행하는 프로그램은 아래처럼 외부 스크립트 파일을 전체 경로로 지정하는 방법도 사용합니다.

- `파일2`{:.success} 반드시 전체 경로로 지정하는 방법도 있지만 이식성이 낮다.

    ```
    #!/bin/sh
     
    /home/user1/myapp/start.sh
    /home/user1/myapp/end.sh
    ```

하지만 이때 스크립트가 있는 디렉터리(myapp) 이름이 바뀌면 문제가 생기며 이식성도 낮습니다. 따라서 상대 경로를 사용하고 싶기 마련입니다. 이런 문제를 해결하려면 셸 스크립트가 일단 **'자신이 지정된 디렉터리에 cd 명령어로 이동해서 처리를 시작하도록'** 만들면 됩니다.

`1`{:.info}에서 사용하는 **dirname 명령어**는 전체 경로가 오면 디렉터리 부분을 추출할 수 있습니다. $0은 실행된 셸의 명령어 자체를 뜻하는 변수로 이 예제에서는 "/home/user1/myapp/dirname.sh"가 들어 있습니다.

- 디렉터리 부분을 추출하는 dirname 명령어

    ```
    $ dirname "/home/user1/myapp/dirname.sh"
    /home/user1/myapp
    ```

한편, $()은 **명령어 치환** 표기로 명령어 출력을 그대로 스크립트에서 이용할 수 있습니다. 즉 `1`{:.info}은 'dirname "$0" 출력 결과 디렉터리에 cd 명령어로 이동한다' 라는 의미입니다. 이 예제에서라면 /home/user1/myapp 디렉터리에 cd 명령어로 이동합니다.

이렇게 하면 셸 스크립트는 자신이 존재하는 디렉터리로 cd 명령어를 써서 이동할 수있습니다. 따라서 상대 경로이거나 절대 경로이거나 상관없이 외부 셸 스크립트를 상대 경로로 실행할 수 있습니다.

&nbsp;
&nbsp;

## **주의사항**

- 디렉터리명에 스페이스(공백문자)가 포함되더라도 정상적으로 동작하도록 `1`{:.info}에서 $0 및 명령어 치환 전체를 큰따옴표 기호로 감쌉니다.

- dirname 명령어를 쓰지 않아도 다음처럼 작성할 수 있습니다.

    ```
    cd "${0%/*}"
    ```

    이것은 셸 **파라미터 확장**을 이용한 예입니다. ${parameter%word}라고 하면 변수 parameter 값에서 word에 후방 일치하는 부분을 삭제한 값을 취득할 수 있습니다. 즉 word로 /*가 지정되었으므로 '변수 $0 뒤에서부터 "/임의의 문자열"을 삭제한 값' 즉, 디렉터리 부분만 얻을 수 있습니다. dirname 명령어라는 외부 명령어를 쓰지 않아도 셸 기능만으로 구현 가능하므로 이쪽을 선호하는 사람도 있습니다.
