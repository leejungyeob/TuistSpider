# TuistSpider

Tuist가 만들어주는 전체 dependency graph는 모듈 수가 많아지면 읽기가 거의 불가능해집니다.  
`TuistSpider`는 Tuist 프로젝트의 그래프를 가져와서, 내가 보고 싶은 모듈 주변만 빠르게 좁혀 보는 macOS 전용 로컬 앱입니다.

## 문제의식

- 전체 그래프 이미지는 모듈이 많아질수록 시각적으로 과밀해집니다.
- 실제로는 "이 모듈이 무엇을 의존하는지", "누가 이 모듈을 참조하는지"만 빠르게 보고 싶은 경우가 많습니다.
- 서드파티와 내부 모듈을 분리해서 봐야 할 때가 많습니다.

## 주요 기능

- Tuist 프로젝트 폴더를 직접 열어서 내부에서 `tuist graph --format json` 실행
- 이미 export된 JSON 파일 직접 열기
- 중심 모듈 선택 후 `양방향`, `의존하는 쪽`, `의존받는 쪽` 전환
- depth 제한
- 외부 의존성 포함 여부 토글
- `펼쳐서 보기` / `계층 묶음 보기` 전환
- 계층 묶음 보기에서 같은 level의 노드를 하나의 카드로 집계
- 계층 카드 클릭 시 포함된 모듈 목록을 오른쪽 패널에 표시
- 그래프 줌/팬 지원

## 지원 플랫폼

- macOS
- SwiftUI 기반 네이티브 앱

## 요구 사항

- Xcode
- Tuist CLI
- macOS에서 `tuist` 실행 가능 상태

예시:

```bash
brew install tuist
```

## 빠른 시작

### 앱 바로 실행

```bash
./scripts/run_mac_app.sh
```

이 스크립트가 아래를 처리합니다.

- `tuist generate`
- `xcodebuild`로 앱 빌드
- `TuistSpider.app` 실행

### Xcode로 열기

```bash
./scripts/open_mac_app.sh
```

## 앱 사용 방법

### 1. 프로젝트 열기

- 앱 상단의 `프로젝트 열기` 클릭
- Tuist 프로젝트 루트 폴더 선택
- 앱이 내부에서 `tuist graph --format json`을 실행해 그래프를 로드

### 2. JSON 열기

- 이미 저장된 그래프 JSON이 있다면 `JSON 열기`로 직접 로드 가능

### 3. 그래프 좁혀 보기

- 왼쪽 목록에서 기준 모듈 선택
- 방향 선택
- depth 선택
- 외부 의존성 포함 여부 전환

### 4. 그래프 표현 방식 전환

- `펼침`
  - 각 모듈을 개별 카드로 표시
- `계층`
  - 같은 level의 노드를 하나의 계층 카드로 묶어서 표시
  - 계층 카드를 누르면 오른쪽에 그 계층에 속한 모듈 리스트가 표시됨

## 그래프 조작

- 오른쪽 위 줌 패널로 확대/축소
- 트랙패드 pinch 줌
- `space + drag`로 캔버스 이동
- `control + wheel`로 확대/축소

## 외부 의존성 처리

외부 의존성 토글은 아래 케이스를 external로 처리합니다.

- Tuist dependency kind가 `package`, `packageProduct`, `external`, `sdk`, `framework`, `xcframework`, `library` 등인 경우
- 경로가 프로젝트 루트 밖에 있는 경우
- 경로에 `checkouts`, `SourcePackages`, `.build`, `.cache`, `CocoaPods`, `Carthage` 등이 포함된 경우

즉, Tuist가 서드파티를 `project/target` 형태로 풀어줘도 경로 기반으로 외부 의존성으로 다시 분류합니다.

## `tuist`를 못 찾는 경우

GUI 앱 실행 환경에서는 터미널 PATH가 그대로 전달되지 않을 수 있습니다.  
그럴 때는 아래처럼 `TUIST_EXECUTABLE`을 직접 넘길 수 있습니다.

```bash
TUIST_EXECUTABLE=/opt/homebrew/bin/tuist ./scripts/run_mac_app.sh
```

## 웹 버전

브라우저로 보는 기존 정적 버전도 같이 들어 있습니다.

```bash
./scripts/run_tuist_spider.sh /path/to/your/tuist/project
```

## 저장소 구성

- `App/`
  - SwiftUI macOS 앱
- `Project.swift`
  - Tuist manifest
- `scripts/run_mac_app.sh`
  - generate + build + app 실행
- `scripts/open_mac_app.sh`
  - generate + Xcode 열기
- `scripts/export_tuist_graph.sh`
  - Tuist graph export + 정규화
- `scripts/normalize_tuist_graph.py`
  - Tuist `json` / `legacyJSON` 정규화
- `web/`
  - 기존 정적 웹 뷰어
- `examples/TuistFixture`
  - 테스트용 샘플 Tuist 프로젝트

## 개발 메모

- macOS 앱이 메인 진입점입니다.
- 웹 버전은 비교용/보조용으로 유지합니다.
- 현재 그래프는 "중심 모듈 기준 서브그래프 탐색"에 초점을 둡니다.
- 레이아웃은 전체 자동 배치 엔진이 아니라, level 기반으로 읽기 쉽게 정렬하는 방식입니다.

## 앞으로 해볼 만한 것

- 계층 카드 펼치기/접기 상태를 캔버스 안에서 직접 토글
- 그래프 검색 결과 하이라이트 강화
- 노드/계층별 색상 구분 개선
- export 결과 캐싱
- 선택한 서브그래프 PNG/SVG 내보내기
