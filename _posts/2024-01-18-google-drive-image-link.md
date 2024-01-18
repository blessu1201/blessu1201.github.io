---
layout: article
title: Github pages 에서 변경된 google drive image 링크 주소 사용방법
tags: [github, google-drive, image-link]
key: 20240118-github-blog-google-drive-image-link
---

## Google-drive image 외부 링크시 구글의 url 변경

깃허브 블로그 포스팅하던 중 갑자기 구글 드라이브에 업로드 되어있는 사진들이 갑자기 보이지 않게 되었습니다.  
예전에 갑자기 외부링크 권한이 변경된 적이 있어, 드라이브에 외부링크 권한이 변경되었는지 확인하였으나,  
이상을 발견하지 못했고, 한참을 구글링하다가 비슷한 문제가 발생한 어느 외국인에게 도움을 요청하여 해결하였습니다.  
하기 이슈트래커를 통해서도 아래와 같이 url 형식이 변경된 것을 확인 하실 수 있습니다.  

Google issue tracker: <https://issuetracker.google.com/issues/319531488?pli=1>

&nbsp;
&nbsp;

> 기존 링크 url 형식

```html
<img src="https://drive.google.com/uc?export=view&id=xxxxxxx">
```

&nbsp;

> 변경된 링크 url 형식 

- `uc?export=view&`{:.info} => `thumbnail?`{:.info} 로 변경해주고 사진의 크기를 키워주기 위해 `&sz=w1000`{:.info} 을 뒤에 붙여줍니다.

```html
<img src="https://drive.google.com/thumbnail?id=xxxxxxx&sz=w1000">
```

&nbsp;

깃허브에서 블로그를 운영하시는 분들은 참고하시길 바랍니다.  
하기 링크(참고자료)에서 소스코드를 공개해주셔서 변경된 사항을 살짝 수정하여, 하단에 주소 자동 변환기를 게시해 놓았습니다.  
필요하신 분들은 즐겨찾기 하셔서 사용하시기 바랍니다.  

참고자료: <https://www.somanet.xyz/2017/06/blog-post_21.html>

## google drive 외부사이트에서 링크 시 주소 자동 변환하기

  <style>
    #converter {
      padding: 20px 20px;
      border-radius: 5px;
      background-color: #f8f8f8;
      width: 100%;
      padding: 15px 15px;
    }

    #converter textarea {
      display: block;
      white-space: wrap;
      background-color: #eee;
      color: #000;
      border: 1px solid #888;
      border-radius: 5px;
      margin-bottom: 10px;
      padding: 5px 5px;
      width: 100%;
      height: 60px;
    }

    #converter input{

    }

    #converter label {
      font-weight: bold;
      color: #333;
    }

    #converter button {
      font-weight: bold;
    }

    #btn-convert {
      width: 100%;
      color: #fff
      border: 1px solid #888;
      border-radius: 5px;
      background-color: #3282F6;
      padding: 5px 5px;
    }

    #btn-convert:active {
      width: 100%;
      color: #fff
      border: 1px solid #fffd55;
      border-radius: 5px;
      background-color: #183f78;
      padding: 5px 5px;
    }

    #convert-result {
      margin-top: 20px;
    }

    #btn-save-result-cb, #btn-save-result-img-tag-cb {
      border: 1px solid #888;
      border-radius: 5px;
      background-color: #147A2E;
      padding: 5px 5px;
    }

    #btn-save-result-cb:active, #btn-save-result-img-tag-cb:active {
      border: 1px solid #fffd55;
      border-radius: 5px;
      background-color: #0c471b;
      padding: 5px 5px
  </style>

<body>
  <div id="converter">
    <label>Google Drive path</label>
    <textarea id="gd-url" placeholder="Input Google Drive Url"></textarea>
    <button id="btn-convert" class="btn btn-primary">Make Google Drive Path Linkable</button>
    <div id="convert-result">
      <label for="result">Linkable Image path</label>
      <textarea id="result" name="result" readonly></textarea>
      <button id="btn-save-result-cb" class="btn btn-success pull-right" data-clipboard-target="#result">
        <span class="glyphicon glyphicon-copy" aria-hidden="true"></span>
        Save to Clipboard
      </button>
      <br><br>
      <label for="result-img-tag">Image Tag</label>
      <textarea id="result-img-tag" name="result" readonly></textarea>
      <button id="btn-save-result-img-tag-cb" class="btn btn-success pull-right" data-clipboard-target="#result-img-tag">
        <span class="glyphicon glyphicon-copy" aria-hidden="true"></span>
        Save to Clipboard
      </button>
    </div>
    <br><br><br>
      <p align="center">
      <b>Preview image</b>
      </p>
    <p align="center">
      <img id="preview" alt="image preview" src='https://www.google.com/drive/static/images/drive/logo-drive.png' class="img-thumbnail" style="max-width: 100%"/><br>
    </p>

  </div>

  <script src="https://ajax.googleapis.com/ajax/libs/jquery/3.2.1/jquery.min.js"></script>
  <script src="https://cdnjs.cloudflare.com/ajax/libs/clipboard.js/1.7.1/clipboard.min.js"></script>
  <script>
    var gdUrl = $("#gd-url");
    $("#btn-convert").on("click", function(event) {

      if (!isValidUrl(gdUrl.val())) {
        alert("You have inputted invalid path.");
        gdUrl.val("");
        return;
      }

      var gdId = extractFileId(gdUrl.val());
      var prefix = "http://drive.google.com/thumbnail?id=";
      var size ="&sz=w1000";
      $("#result").val(prefix + gdId + size);
      $("#result-img-tag").val(
        "<img src='" +
        prefix + gdId + size +
        "' /><br>");
      $("#preview").attr("src", prefix + gdId + size);
    });

    var clipboard = new Clipboard('.btn');

    clipboard.on('success', function(e) {
      console.info('Action:', e.action);
      console.info('Text:', e.text);
      console.info('Trigger:', e.trigger);

      e.clearSelection();
    });

    clipboard.on('error', function(e) {
      console.error('Action:', e.action);
      console.error('Trigger:', e.trigger);
    });

    // validity check. ref: https://gist.github.com/jlong/2428561
    function isValidUrl(url) {
      // to be impl...
      var parser = document.createElement('a');
      parser.href = url;

      if(url === '' || parser.hostname !== "drive.google.com" || !parser.pathname.includes("/file/d/"))
        return false;

      return true;
    }

    function extractFileId(url) {
      if (!url) 
        url = window.location.href;

      var strip = url.replace(/https:\/\/drive.google.com\/file\/d\//gi, "")
      .replace(/\/view\?[a-zA-Z=\/]+/gi, "");
      
      return strip;
    }
  </script>
</body>