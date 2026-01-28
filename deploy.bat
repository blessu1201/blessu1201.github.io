:: 배포 스크립트
:: Git 저장소의 변경 사항을 커밋하고 푸시합니다.
@echo off

echo update 된 항목 추가
git add -A

echo commit & description
git commit -m 'update'

echo 배포
git push
