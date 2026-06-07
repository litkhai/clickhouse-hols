-- ============================================================================
-- Full-Text Search Lab · Step 2: Generate 1M Bilingual Support Tickets
-- 풀텍스트 검색 실습 · Step 2: 한/영 고객지원 티켓 1백만 건 생성
-- ============================================================================
-- Strategy: build text out of pools of realistic snippets and concat() them
--           into subject + body. ~70% Korean, ~20% mixed ko/en, ~10% English,
--           matching the population of a Korean SaaS commerce platform.
--
-- We generate ONCE into tickets_noidx, then copy into the three indexed
-- variants. This guarantees identical data across all four tables so the
-- comparisons in step 04 are apples-to-apples.
--
-- Total runtime on a 16-CPU Cloud service: ~3-5 minutes for tickets,
-- ~1 minute for messages, <1 second for articles.
-- ============================================================================

SET max_insert_threads = 8;
SET max_block_size = 100000;

-- ----------------------------------------------------------------------------
-- 2.1 Generate 1,000,000 tickets into the baseline (un-indexed) table.
-- 2.1 베이스라인 (인덱스 없는) 테이블에 100만 건 생성
-- ----------------------------------------------------------------------------
-- All randomness is seeded by `number` so reruns reproduce the same data.
-- 모든 난수는 number를 기반으로 하므로 재실행 시 동일한 데이터가 생성됨.
-- ----------------------------------------------------------------------------
INSERT INTO support_search.tickets_noidx
WITH
    -- ---- Korean subject pool (organized by category) ------------------------
    ko_subj_billing AS (SELECT [
        '결제가 진행되지 않습니다',
        '카드 결제 실패 문의드립니다',
        '결제 오류 PAYMENT_DECLINED 발생',
        '결제는 됐는데 주문이 안 들어갔어요',
        '결제하다가 페이지가 멈췄어요',
        '카카오페이 결제가 안돼요',
        '간편결제 등록이 안 됩니다',
        '결제 수단 변경 부탁드립니다',
        '이중 결제 된 것 같아요',
        '쿠폰 적용이 안 되는데 결제됐어요'
    ] AS arr),
    ko_subj_shipping AS (SELECT [
        '배송이 너무 늦어지고 있어요',
        '배송 시작했다고 떴는데 운송장이 없어요',
        '주문한 지 일주일째 배송 안 와요',
        '배송지 변경 부탁드립니다',
        '택배 받았는데 박스가 손상되어 있어요',
        '배송 추적이 안 됩니다',
        '주말 배송 가능한가요',
        '제주도 배송비 문의',
        '배송 출발 안내가 안 와요',
        '배송완료 처리됐는데 물건이 없어요'
    ] AS arr),
    ko_subj_refund AS (SELECT [
        '환불은 언제 처리되나요',
        '환불 신청했는데 답변이 없어요',
        '단순 변심 환불 가능한가요',
        '환불 받았는데 금액이 적게 들어왔어요',
        '교환 대신 환불 부탁드립니다',
        '취소했는데 환불이 안 됐어요',
        '부분 환불 요청합니다',
        '환불 거절 사유 알려주세요',
        '환불 처리 기간이 너무 길어요',
        '카드 환불 영업일 안내 부탁'
    ] AS arr),
    ko_subj_login AS (SELECT [
        '로그인이 안 됩니다',
        '비밀번호 재설정이 안돼요',
        '계정이 잠겼다고 떠요',
        '소셜 로그인 오류',
        '2단계 인증 코드가 안 와요',
        '로그인하면 바로 튕겨요',
        '아이디 찾기가 안 됩니다',
        '카카오 연동 로그인 실패',
        '로그인 안됨 - 비밀번호 맞는데도',
        '구글 로그인 시 에러 발생'
    ] AS arr),
    ko_subj_account AS (SELECT [
        '회원 탈퇴 신청합니다',
        '이메일 주소 변경 부탁드립니다',
        '휴면 계정 복구 요청',
        '개인정보 수정이 안돼요',
        '본인 인증이 계속 실패합니다',
        '주소록에서 기본 배송지 변경 안돼요',
        '회원 등급이 잘못 표시되어 있어요',
        '포인트가 적립 안 됩니다',
        '쿠폰함이 안 열려요',
        '닉네임 변경 불가 안내'
    ] AS arr),
    ko_subj_bug AS (SELECT [
        '앱이 자꾸 강제 종료됩니다',
        '장바구니에 담은 상품이 사라져요',
        '검색 결과가 이상하게 나옵니다',
        '리뷰 작성 시 오류 발생',
        '주문 상세 페이지가 안 열려요',
        '모바일에서 결제 버튼이 안 보여요',
        '이미지가 로딩이 안돼요',
        '필터링이 작동하지 않습니다',
        '주문 내역이 일부만 보입니다',
        '푸시 알림이 중복으로 옵니다'
    ] AS arr),
    ko_subj_feature AS (SELECT [
        '위시리스트 폴더 기능 제안',
        '다크 모드 지원해 주세요',
        '재입고 알림 받고 싶어요',
        '주문 자동 반복 결제 기능',
        '리뷰 사진 일괄 업로드 기능',
        '배송지 여러 개 동시 등록 요청',
        '결제 수단에 토스페이 추가 요청',
        '카테고리 즐겨찾기 기능 부탁',
        '주문 후 영수증 PDF 다운로드',
        '구독 기능 도입 제안'
    ] AS arr),
    ko_subj_howto AS (SELECT [
        '쿠폰 사용 방법이 궁금해요',
        '교환 신청 어떻게 하나요',
        '포인트 사용 방법 알려주세요',
        '비회원 주문 조회 방법',
        '리뷰 작성 시 사진 첨부 방법',
        '세금계산서 발행 방법',
        '회사 인증 절차 안내',
        '대량 주문은 어디로 문의하나요',
        '해외 배송 가능한가요',
        '예약 주문 어떻게 하는 건가요'
    ] AS arr),
    -- ---- English subject pool ----------------------------------------------
    en_subjects AS (SELECT [
        'Cannot complete checkout - card declined',
        'Refund still pending after 7 days',
        'Shipment stuck at customs',
        'Login keeps redirecting to home',
        'Two-factor auth code never arrives',
        'Account locked after password reset',
        'Wrong item received in order',
        'App crashes on payment screen',
        'Coupon code not applying',
        'Subscription renewal failed',
        'Cannot delete payment method',
        'Bug: order history empty',
        'Feature request: dark mode',
        'How do I request tax invoice',
        'Address book sync issue'
    ] AS arr),
    -- ---- Mixed ko+en subject pool (very common in Korean SaaS) -------------
    mx_subjects AS (SELECT [
        'iPhone 15 Pro 배송 지연 문의',
        'Galaxy Watch 환불 요청합니다',
        'PAYMENT_DECLINED 오류로 결제 실패',
        'ERROR 502 발생 - 로그인 불가',
        'MacBook Air 주문 취소 부탁',
        'Sony WH-1000XM5 박스 손상',
        '카드 결제 시 TIMEOUT 발생',
        'AirPods Pro 재입고 알림 요청',
        'Nike 신발 size 교환',
        'Dyson V15 배송 추적 안됨',
        '쿠팡 partner ID 변경 요청',
        'OAuth 로그인 실패 - Google',
        'Stripe checkout error 발생',
        'SAMSUNG 모니터 DOA 환불',
        'LG 전자레인지 A/S 문의'
    ] AS arr),

    -- ---- Body opener pools --------------------------------------------------
    ko_openers AS (SELECT [
        '안녕하세요. ',
        '담당자님 안녕하세요. ',
        '문의드립니다. ',
        '도움이 필요해서 글 남깁니다. ',
        '빠른 처리 부탁드립니다. ',
        '며칠 전부터 문제가 있어서 연락드립니다. ',
        '답답해서 글 올립니다. ',
        '여러 번 시도해봤는데 안 됩니다. ',
        '바쁘신데 죄송합니다. ',
        '확인 부탁드립니다. '
    ] AS arr),
    ko_middles AS (SELECT [
        '주문번호 ',
        '회원ID ',
        '결제 시도한 카드 끝번호 ',
        '문의 번호 '
    ] AS arr),
    ko_closers AS (SELECT [
        ' 빠른 답변 부탁드립니다. 감사합니다.',
        ' 환불 부탁드립니다.',
        ' 어떻게 해야 하나요?',
        ' 답변 기다리겠습니다.',
        ' 너무 답답합니다. 도와주세요.',
        ' 처리해주시면 감사하겠습니다.',
        ' 같은 문제 또 생기면 안 되니까 원인도 알려주세요.',
        ' 빠른 대응 부탁드립니다.',
        ' 감사합니다.',
        ' 잘 부탁드립니다.'
    ] AS arr),
    en_openers AS (SELECT [
        'Hi team, ',
        'Hello, ',
        'Hi support, ',
        'Dear team, ',
        'To whom it may concern, '
    ] AS arr),
    en_closers AS (SELECT [
        ' Please look into this asap.',
        ' Thanks in advance.',
        ' Looking forward to your reply.',
        ' Please escalate if needed.',
        ' Best regards.'
    ] AS arr),

    -- ---- Anchored detail snippets that we will search for later ------------
    -- These guarantee specific recall numbers for benchmarking.
    -- 나중에 검색할 앵커 구문들 — 정확한 recall 측정을 위한 보장된 데이터.
    ko_details_payment AS (SELECT [
        '결제가 안 됩니다. 카드는 다른 곳에서는 잘 됩니다. ',
        '결제 실패 후에 카드사에 확인해보니 정상이라고 합니다. ',
        '결제가 진행되다가 마지막에 오류 메시지 없이 멈춥니다. ',
        '간편결제로 시도해도 동일하게 결제가 안돼요. ',
        '결제 시도하면 PAYMENT_DECLINED 오류가 발생합니다. ',
        '결제수단 등록부터가 안 됩니다. '
    ] AS arr),
    ko_details_shipping AS (SELECT [
        '배송이 7일째 안 오고 있습니다. ',
        '운송장 번호가 부여됐는데 조회가 안 됩니다. ',
        '배송 출발 안내 이후로 업데이트가 없어요. ',
        '배송 지연 이유라도 알려주세요. ',
        '배송기사님이 임의로 경비실에 두고 가셨어요. ',
        '배송 추적 페이지에서 오류가 납니다. '
    ] AS arr),
    ko_details_refund AS (SELECT [
        '환불이 7영업일 지났는데 입금이 안 됐어요. ',
        '환불 거절됐는데 사유를 모르겠습니다. ',
        '부분 환불 가능한지 알려주세요. ',
        '환불 받았는데 배송비가 차감되어 있습니다. ',
        '환불 처리 상태가 며칠째 “접수”로만 떠 있어요. ',
        '카드 취소 환불 영업일 안내 부탁드려요. '
    ] AS arr),
    ko_details_login AS (SELECT [
        '비밀번호를 정확히 입력해도 로그인이 안돼요. ',
        '비밀번호 재설정 메일이 오지 않습니다. ',
        '계정 잠금 해제 부탁드립니다. ',
        '2차 인증 번호가 도착하지 않습니다. ',
        '소셜 로그인 시 권한 오류가 납니다. ',
        '로그인 후 바로 로그아웃 됩니다. '
    ] AS arr),
    ko_details_generic AS (SELECT [
        '재현 단계: 1. 로그인 2. 장바구니 3. 결제 진행 4. 오류. ',
        '같은 문제를 친구도 겪고 있다고 합니다. ',
        '캐시 삭제, 앱 재설치 모두 해봤습니다. ',
        '모바일 앱과 PC 웹 모두 동일 증상입니다. ',
        '와이파이와 LTE 모두 시도해봤습니다. ',
        '브라우저는 Chrome 최신 버전입니다. '
    ] AS arr),
    en_details AS (SELECT [
        'I have tried clearing cache and reinstalling the app. ',
        'My card works fine on other sites. ',
        'Order ID is ',
        'This started happening 3 days ago. ',
        'Error message: PAYMENT_DECLINED. ',
        'Status has been stuck at "processing" for a week. '
    ] AS arr),
    products AS (SELECT [
        'iPhone 15 Pro','Galaxy S24 Ultra','MacBook Air M3','iPad Pro',
        'AirPods Pro','Galaxy Watch 7','Sony WH-1000XM5','Dyson V15',
        'Nintendo Switch OLED','LG 그램 17','삼성 노트북','LG 모니터 32UP850',
        'Nike Air Max','Adidas Ultraboost','Samsung 비스포크 냉장고','LG 트롬 세탁기',
        '쿠팡 PB 생수','Stanley 텀블러','Coleman 텐트','Yeti 쿨러'
    ] AS arr),
    categories AS (SELECT
        ['billing','shipping','refund','login','account','bug','feature','howto'] AS arr,
        [25, 20, 15, 10, 8, 12, 5, 5] AS weights -- approximate distribution
    ),
    channels AS (SELECT ['email','chat','web','mobile_app','phone'] AS arr),
    -- Language mix: 70% ko, 20% mixed, 10% en
    languages AS (SELECT ['ko','ko','ko','ko','ko','ko','ko','mixed','mixed','en'] AS arr)

SELECT
    number + 1 AS ticket_id,
    (cityHash64(number, 'cust') % 250000) + 1 AS customer_id,
    (cityHash64(number, 'agent') % 200) + 1 AS agent_id,

    -- Category picked by weighted index (8 categories with rough weights)
    arrayElement(
        (SELECT arr FROM categories),
        ((cityHash64(number, 'cat') % 100) < 25) * 1
        + ((cityHash64(number, 'cat') % 100) >= 25 AND (cityHash64(number, 'cat') % 100) < 45) * 2
        + ((cityHash64(number, 'cat') % 100) >= 45 AND (cityHash64(number, 'cat') % 100) < 60) * 3
        + ((cityHash64(number, 'cat') % 100) >= 60 AND (cityHash64(number, 'cat') % 100) < 70) * 4
        + ((cityHash64(number, 'cat') % 100) >= 70 AND (cityHash64(number, 'cat') % 100) < 78) * 5
        + ((cityHash64(number, 'cat') % 100) >= 78 AND (cityHash64(number, 'cat') % 100) < 90) * 6
        + ((cityHash64(number, 'cat') % 100) >= 90 AND (cityHash64(number, 'cat') % 100) < 95) * 7
        + ((cityHash64(number, 'cat') % 100) >= 95) * 8
    ) AS category,

    -- Priority skewed toward medium/low
    CAST(arrayElement([1,2,3,3,3,4,4,4,4,4], (cityHash64(number, 'prio') % 10) + 1) AS Enum8('critical'=1,'high'=2,'medium'=3,'low'=4)) AS priority,

    -- Status skewed toward resolved/closed (real ops mix)
    CAST(arrayElement([1,2,2,3,4,4,4,4,5,5,5,5], (cityHash64(number, 'stat') % 12) + 1) AS Enum8('open'=1,'in_progress'=2,'pending'=3,'resolved'=4,'closed'=5)) AS status,

    arrayElement((SELECT arr FROM channels), (cityHash64(number, 'ch') % 5) + 1) AS channel,
    arrayElement((SELECT arr FROM products), (cityHash64(number, 'prod') % 20) + 1) AS product,
    arrayElement((SELECT arr FROM languages), (cityHash64(number, 'lang') % 10) + 1) AS language,

    -- Subject — picked from a different pool based on category & language
    multiIf(
        language = 'en',
            arrayElement((SELECT arr FROM en_subjects), (cityHash64(number, 'sub_en') % 15) + 1),
        language = 'mixed',
            arrayElement((SELECT arr FROM mx_subjects), (cityHash64(number, 'sub_mx') % 15) + 1),
        category = 'billing',
            arrayElement((SELECT arr FROM ko_subj_billing),  (cityHash64(number, 'sub') % 10) + 1),
        category = 'shipping',
            arrayElement((SELECT arr FROM ko_subj_shipping), (cityHash64(number, 'sub') % 10) + 1),
        category = 'refund',
            arrayElement((SELECT arr FROM ko_subj_refund),   (cityHash64(number, 'sub') % 10) + 1),
        category = 'login',
            arrayElement((SELECT arr FROM ko_subj_login),    (cityHash64(number, 'sub') % 10) + 1),
        category = 'account',
            arrayElement((SELECT arr FROM ko_subj_account),  (cityHash64(number, 'sub') % 10) + 1),
        category = 'bug',
            arrayElement((SELECT arr FROM ko_subj_bug),      (cityHash64(number, 'sub') % 10) + 1),
        category = 'feature',
            arrayElement((SELECT arr FROM ko_subj_feature),  (cityHash64(number, 'sub') % 10) + 1),
        arrayElement((SELECT arr FROM ko_subj_howto),        (cityHash64(number, 'sub') % 10) + 1)
    ) AS subject,

    -- Body composed of opener + 1-2 detail snippets + product mention + closer
    multiIf(
        language = 'en',
            concat(
                arrayElement((SELECT arr FROM en_openers), (cityHash64(number, 'eo') % 5) + 1),
                'I am having issues with my recent order. ',
                arrayElement((SELECT arr FROM en_details), (cityHash64(number, 'ed1') % 6) + 1),
                arrayElement((SELECT arr FROM en_details), (cityHash64(number, 'ed2') % 6) + 1),
                toString((cityHash64(number, 'oid') % 9000000) + 1000000), '. ',
                'Product: ', arrayElement((SELECT arr FROM products), (cityHash64(number, 'prod') % 20) + 1), '.',
                arrayElement((SELECT arr FROM en_closers), (cityHash64(number, 'ec') % 5) + 1)
            ),
        language = 'mixed',
            concat(
                arrayElement((SELECT arr FROM ko_openers), (cityHash64(number, 'mo') % 10) + 1),
                arrayElement((SELECT arr FROM products), (cityHash64(number, 'prod') % 20) + 1), ' ',
                multiIf(
                    category = 'billing',  arrayElement((SELECT arr FROM ko_details_payment),  (cityHash64(number, 'md') % 6) + 1),
                    category = 'shipping', arrayElement((SELECT arr FROM ko_details_shipping), (cityHash64(number, 'md') % 6) + 1),
                    category = 'refund',   arrayElement((SELECT arr FROM ko_details_refund),   (cityHash64(number, 'md') % 6) + 1),
                    category = 'login',    arrayElement((SELECT arr FROM ko_details_login),    (cityHash64(number, 'md') % 6) + 1),
                    arrayElement((SELECT arr FROM ko_details_generic), (cityHash64(number, 'md') % 6) + 1)
                ),
                'Order ID: ', toString((cityHash64(number, 'oid') % 9000000) + 1000000), '. ',
                arrayElement((SELECT arr FROM ko_closers), (cityHash64(number, 'mc') % 10) + 1)
            ),
        -- Korean default
        concat(
            arrayElement((SELECT arr FROM ko_openers), (cityHash64(number, 'ko') % 10) + 1),
            multiIf(
                category = 'billing',  arrayElement((SELECT arr FROM ko_details_payment),  (cityHash64(number, 'kd1') % 6) + 1),
                category = 'shipping', arrayElement((SELECT arr FROM ko_details_shipping), (cityHash64(number, 'kd1') % 6) + 1),
                category = 'refund',   arrayElement((SELECT arr FROM ko_details_refund),   (cityHash64(number, 'kd1') % 6) + 1),
                category = 'login',    arrayElement((SELECT arr FROM ko_details_login),    (cityHash64(number, 'kd1') % 6) + 1),
                arrayElement((SELECT arr FROM ko_details_generic), (cityHash64(number, 'kd1') % 6) + 1)
            ),
            arrayElement((SELECT arr FROM ko_details_generic), (cityHash64(number, 'kd2') % 6) + 1),
            arrayElement((SELECT arr FROM ko_middles), (cityHash64(number, 'km') % 4) + 1),
            toString((cityHash64(number, 'oid') % 9000000) + 1000000), '. ',
            '제품: ', arrayElement((SELECT arr FROM products), (cityHash64(number, 'prod') % 20) + 1), '.',
            arrayElement((SELECT arr FROM ko_closers), (cityHash64(number, 'kc') % 10) + 1)
        )
    ) AS body,

    -- Resolution only present on resolved/closed tickets
    if(status IN ('resolved','closed'),
        arrayElement([
            '환불 처리 완료했습니다.',
            '재배송 처리 완료 안내드렸습니다.',
            '계정 잠금 해제 완료했습니다.',
            '결제 수단 재등록 안내드렸고 정상 처리됨을 확인했습니다.',
            'Refunded to original payment method.',
            'Replacement shipped, tracking provided.',
            'Account unlocked and 2FA re-enabled.',
            '쿠폰 재발급 후 결제 정상 완료 확인.',
            '운영팀 이관 후 처리 완료.',
            'Closed - duplicate of #' || toString((cityHash64(number, 'dup') % 1000000) + 1)
        ], (cityHash64(number, 'res') % 10) + 1),
        ''
    ) AS resolution,

    [category, channel,
     if(cityHash64(number, 'tag1') % 3 = 0, 'vip', 'standard'),
     if(language = 'ko', 'lang_ko', if(language = 'en', 'lang_en', 'lang_mixed'))
    ] AS tags,

    -- created_at spread over the last 180 days
    now() - INTERVAL (cityHash64(number, 'time') % 15552000) SECOND AS created_at,
    if(status IN ('resolved','closed'),
        created_at + INTERVAL ((cityHash64(number, 'rt') % 432000) + 600) SECOND,
        NULL
    ) AS resolved_at
FROM numbers(1000000);

-- ----------------------------------------------------------------------------
-- 2.2 Mirror the data into the three indexed variants (identical rows).
-- 2.2 동일한 데이터를 인덱스가 있는 세 가지 변형 테이블로 복사.
-- ----------------------------------------------------------------------------
INSERT INTO support_search.tickets_token  SELECT * FROM support_search.tickets_noidx;
INSERT INTO support_search.tickets_ngram  SELECT * FROM support_search.tickets_noidx;
INSERT INTO support_search.tickets_text   SELECT * FROM support_search.tickets_noidx;

-- ----------------------------------------------------------------------------
-- 2.3 Knowledge base articles (200 KB FAQs for FAQ-matching scenarios)
-- 2.3 지식베이스 문서 (FAQ 매칭 시나리오용)
-- ----------------------------------------------------------------------------
INSERT INTO support_search.articles (article_id, category, language, title, body, keywords, views, helpful_votes)
VALUES
    (1, 'billing','ko','결제 실패 시 확인 사항','결제가 실패하는 가장 흔한 원인은 카드 한도, 해외 결제 차단, 그리고 카드사 점검 시간입니다. 결제가 안 될 때는 우선 다른 카드로 시도해 보시고, 카카오페이/네이버페이 같은 간편결제도 시도해 주세요. 그래도 결제가 안 되면 PAYMENT_DECLINED 오류 코드와 함께 문의 부탁드립니다.', ['결제','실패','카드','PAYMENT_DECLINED'], 12450, 980),
    (2, 'billing','ko','이중 결제 환불 안내','이중 결제가 의심되는 경우 주문 내역에서 중복 주문 여부를 먼저 확인해 주세요. 카드사 매입 전이라면 결제 취소가 즉시 가능하며, 매입 후라면 영업일 기준 3~7일 이내 환불 처리됩니다.', ['이중결제','중복','환불'], 8210, 612),
    (3, 'shipping','ko','배송 지연 안내','일반 배송 기준 2영업일 이내 출고됩니다. 도서산간 지역은 추가로 1~2일 소요됩니다. 운송장 번호가 부여됐는데 조회되지 않으면 배송업체에서 스캔이 늦은 경우이니 6시간 이내 다시 시도해 주세요.', ['배송','지연','운송장','도서산간'], 18030, 1521),
    (4, 'refund','ko','환불 처리 영업일 안내','신용카드 환불은 카드사 매입 여부에 따라 처리 기간이 달라집니다. 카드 취소는 영업일 기준 3~5일, 매입 후 취소는 7~14일까지 소요될 수 있습니다.', ['환불','영업일','카드'], 9870, 720),
    (5, 'login','ko','로그인 안 될 때','비밀번호를 잊으셨다면 비밀번호 재설정을, 계정이 잠겼다면 본인 인증 후 잠금 해제가 가능합니다. 2단계 인증 코드가 오지 않으면 스팸함을 확인하거나 SMS 수신 차단 여부를 확인해 주세요.', ['로그인','비밀번호','2단계','계정잠금'], 15400, 1100),
    (6, 'account','ko','회원 탈퇴 절차','회원 탈퇴는 마이페이지 > 설정에서 직접 신청 가능합니다. 진행 중인 주문이 있으면 완료 후 탈퇴해 주세요. 탈퇴 시 적립금과 쿠폰은 모두 소멸됩니다.', ['회원탈퇴','계정','적립금'], 4220, 305),
    (7, 'billing','en','Payment failures - what to check','The most common reasons for payment failure are card limits, blocked international transactions, and card-issuer maintenance windows. Try another card and try a simple-pay method like Kakao Pay before contacting support with the PAYMENT_DECLINED error code.', ['payment','failure','PAYMENT_DECLINED'], 6020, 412),
    (8, 'shipping','en','Shipping delays','Standard shipping takes 2 business days. Remote islands require 1-2 extra days. Tracking number may take up to 6 hours to appear in the carrier system.', ['shipping','delay','tracking'], 7110, 540),
    (9, 'login','en','Cannot log in','If you forgot your password, use the password reset flow. If your account is locked, verify your identity to unlock. For missing 2FA codes, check your spam folder.', ['login','password','2fa'], 5210, 380),
    (10,'bug','ko','앱 강제 종료 시 해결 방법','앱이 자꾸 강제 종료된다면 가장 먼저 앱 캐시 삭제와 재설치를 시도해 주세요. iOS는 설정 > 일반 > 저장공간, 안드로이드는 설정 > 앱 > 저장소 메뉴에서 가능합니다.', ['앱','강제종료','캐시'], 11200, 890);

-- ----------------------------------------------------------------------------
-- 2.4 Ticket messages (~2 messages per ticket = 2M rows)
-- 2.4 티켓 메시지 (티켓당 ~2건 = 약 200만 건)
-- ----------------------------------------------------------------------------
INSERT INTO support_search.ticket_messages
WITH
    customer_followups AS (SELECT [
        '아직 답변 못 받았습니다. 빠른 처리 부탁드려요.',
        '며칠째 답이 없는데 어떻게 된 건가요?',
        '추가 정보가 필요하시면 알려주세요.',
        '카드사에 다시 확인해보니 정상이었습니다.',
        'Still waiting for your response on this.',
        'Any update? This has been over 5 days.',
        '같은 문제가 또 발생했어요. 영구적인 해결 부탁드립니다.',
        '환불해주시면 더 이상 문의 안 드릴게요.'
    ] AS arr),
    agent_replies AS (SELECT [
        '안녕하세요, 확인해보겠습니다. 잠시만 기다려 주세요.',
        '주문번호 확인 부탁드립니다.',
        '관련 부서로 이관했습니다. 24시간 내 답변 드리겠습니다.',
        '환불 처리 시작하겠습니다. 영업일 기준 3-5일 소요됩니다.',
        'Apologies for the delay. We have escalated to the relevant team.',
        'I have refunded the original payment method.',
        '재배송 진행했습니다. 운송장은 곧 등록됩니다.',
        '계정 잠금 해제 완료했습니다.'
    ] AS arr)
SELECT
    t.ticket_id,
    seq + 1 AS message_seq,
    CAST(if(seq % 2 = 0, 'customer', 'agent') AS Enum8('customer'=1,'agent'=2,'system'=3)) AS sender,
    t.created_at + INTERVAL ((seq + 1) * 3600 + (cityHash64(t.ticket_id, seq) % 7200)) SECOND AS sent_at,
    if(seq % 2 = 0,
        arrayElement((SELECT arr FROM customer_followups), (cityHash64(t.ticket_id, seq, 'cf') % 8) + 1),
        arrayElement((SELECT arr FROM agent_replies), (cityHash64(t.ticket_id, seq, 'ar') % 8) + 1)
    ) AS body
FROM support_search.tickets_noidx t
ARRAY JOIN range(if(t.status IN ('resolved','closed'), 3, 1)) AS seq;

-- ----------------------------------------------------------------------------
-- 2.5 Sanity counts
-- 2.5 적재 확인
-- ----------------------------------------------------------------------------
SELECT 'tickets_noidx'  AS tbl, count() FROM support_search.tickets_noidx
UNION ALL
SELECT 'tickets_token',  count() FROM support_search.tickets_token
UNION ALL
SELECT 'tickets_ngram',  count() FROM support_search.tickets_ngram
UNION ALL
SELECT 'tickets_text',   count() FROM support_search.tickets_text
UNION ALL
SELECT 'articles',       count() FROM support_search.articles
UNION ALL
SELECT 'ticket_messages',count() FROM support_search.ticket_messages
ORDER BY tbl;

-- Language distribution check
-- 언어별 분포 확인
SELECT language, count(), round(count() * 100.0 / 1000000, 1) AS pct
FROM support_search.tickets_noidx
GROUP BY language
ORDER BY count() DESC;

-- Category distribution check
-- 카테고리별 분포 확인
SELECT category, count() AS n
FROM support_search.tickets_noidx
GROUP BY category
ORDER BY n DESC;
