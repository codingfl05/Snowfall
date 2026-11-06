# Snowfall MVP (개인용)

화면에 눈이 내리고, 열린 창 윗변 위에 쌓이고, 창을 움직이거나 닫으면 쌓인 눈이 떨어지는 macOS 메뉴바 앱.

## 1. 준비 (최초 1회)
터미널에서:
```
xcode-select --install     # 이미 Xcode가 설치돼 있으면 생략
swift --version            # 버전이 출력되면 OK
```

## 2. 프로젝트 열기 + git
zip을 풀고 Antigravity에서 이 폴더를 연 뒤, 터미널에서:
```
git init
git add .
git commit -m "MVP initial"
```
AI가 코드를 망가뜨려도 `git checkout .` 으로 되돌릴 수 있음. 잘 돌아가는 상태마다 commit 할 것.

## 3. 실행
> 참고: 현재 툴체인에서는 `swift build`에 링킹 오류가 발생하므로 제공된 스크립트를 사용합니다.

```
./run.sh
```
- 디버그 로그: `SNOW_DEBUG=1 ./run.sh`
- 빌드만 수행: `./build.sh`
- 종료: 메뉴바 ❄︎ → 종료, 또는 터미널에서 Ctrl + C
- 메뉴: 눈 양 (Light / Normal / Blizzard), 일시정지, 쌓인 눈 털기

## 4. 느낌 조정
`Sources/Snowfall/Config.swift` 의 숫자만 바꾸면 됨. 예:
- 더 빨리 쌓이게: `accumulationPerFlake` ↑
- 더 높이 쌓이게: `maxPileHeight` ↑
- 더 뾰족하게 / 평평하게: `maxSlope` ↑ / ↓
- 바람: `wind`

## 5. 문제 해결
- 컴파일 에러: 에러 메시지 전체를 Antigravity 에이전트에 붙여넣고 수정 요청
- 눈은 내리는데 창에 안 쌓임: `SNOW_DEBUG=1 ./run.sh` 로 실행해서 `windows:` 숫자 확인
  - 0이면 창 감지 문제 → 시스템 설정 > 개인정보 보호 및 보안 > 화면 기록에서 터미널(또는 Antigravity) 허용 후 재실행
- 아무것도 안 보임: 메뉴바에 ❄︎ 가 있는지, 일시정지 상태가 아닌지 확인

## 알려진 한계 (MVP)
- Spaces(데스크톱) 전환 시 모든 창의 눈이 떨어짐
- Dock, 바탕화면 아이콘에는 안 쌓임
