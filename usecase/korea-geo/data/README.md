# Boundary data — not covered by the repository's MIT licence

[English](#english) | [한국어](#한국어)

## English

`sig_4326.geojson` is not original to this repository. It is a simplified,
WGS84 (EPSG:4326) copy of the 251 시군구 (municipality) boundaries from
[`southkorea/southkorea-maps`](https://github.com/southkorea/southkorea-maps),
`kostat/2013`, whose own source is census boundary data published by
[KOSTAT](http://sgis.kostat.go.kr), the Korean statistics office.

**The [root LICENSE](../../../LICENSE) does not apply to this file.** The
upstream repository ships no SPDX licence — its `license/` directory holds the
permission it obtained per source rather than a licence text — so this data
carries whatever terms KOSTAT attaches to it, which are not ours to grant.
Check upstream and KOSTAT before redistributing it or using it beyond running
this lab.

Everything else in `usecase/korea-geo/` — the schema, the loader, the Superset
setup and the documentation — is original and MIT, like the rest of the
repository.

Substituting your own boundary file is supported: `load_geo.py` takes a path,
and the README explains reprojecting from EPSG:5179 if your source needs it.

```bash
python3 scripts/load_geo.py /path/to/your.geojson
```

## 한국어

`sig_4326.geojson`은 이 저장소가 만든 파일이 아닙니다.
[`southkorea/southkorea-maps`](https://github.com/southkorea/southkorea-maps)의
`kostat/2013` 시군구 경계 251개를 WGS84(EPSG:4326)로 단순화한 사본이며, 그
원본은 통계청 [KOSTAT](http://sgis.kostat.go.kr)이 공개한 센서스용 행정구역
경계 데이터입니다.

**[루트 LICENSE](../../../LICENSE)는 이 파일에 적용되지 않습니다.** 상류
저장소에는 SPDX 라이선스가 없고 — `license/` 디렉토리에 라이선스 문안 대신
출처별로 받은 사용 허가 자료가 들어 있습니다 — 따라서 이 데이터에는 KOSTAT이
정한 조건이 그대로 남아 있습니다. 저희가 대신 부여할 수 있는 권리가 아닙니다.
이 랩을 실행하는 것을 넘어 재배포하거나 다른 용도로 쓰기 전에 상류 저장소와
KOSTAT의 조건을 확인하세요.

`usecase/korea-geo/`의 나머지 — 스키마, 로더, Superset 설정, 문서 — 는 모두
직접 작성한 것으로 저장소의 다른 부분과 같이 MIT입니다.

직접 준비한 경계 파일로 대체할 수 있습니다. `load_geo.py`가 경로를 인자로
받고, EPSG:5179 소스의 좌표계 변환 방법은 랩 README에 정리돼 있습니다.

```bash
python3 scripts/load_geo.py /path/to/your.geojson
```
