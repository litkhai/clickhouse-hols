-- Independent checks of the numbers the AI reported (run as the admin, on the view).
SELECT 'p1 top-20 all in archive/images' AS chk, countIf(root = 'archive' AND startsWith(path, 'images/')) AS v FROM (SELECT root, path FROM fileidx.files ORDER BY size DESC LIMIT 20);
SELECT 'p2 duplicate groups / files / wasted bytes' AS chk, tuple(count(), sum(c), sum((c - 1) * s)) AS v FROM (SELECT content_hash, count() AS c, any(size) AS s FROM fileidx.files WHERE content_hash != '' GROUP BY content_hash HAVING c > 1);
SELECT 'p2 same, with empty hashes counted as one group' AS chk, tuple(count(), sum(c), formatReadableSize(sum((c - 1) * s))) AS v FROM (SELECT content_hash, count() AS c, any(size) AS s FROM fileidx.files GROUP BY content_hash HAVING c > 1);
SELECT 'p3 extensions / mp4 files / mp4 bytes' AS chk, tuple(uniqExact(ext), countIf(ext = 'mp4'), formatReadableSize(sumIf(size, ext = 'mp4'))) AS v FROM fileidx.files;
SELECT 'p4 pdf|docx|hwp with 계약 or contract in the name' AS chk, count() AS v FROM fileidx.files WHERE ext IN ('pdf','docx','hwp') AND multiSearchAnyCaseInsensitiveUTF8(name, ['계약','contract']);
SELECT 'p5 2025-03 files / mp4 files / bytes' AS chk, tuple(count(), countIf(ext = 'mp4'), formatReadableSize(sum(size))) AS v FROM fileidx.files WHERE toYYYYMM(mtime) = 202503;
SELECT 'p6 no ext / size 0 / temp (~$, .tmp, .part)' AS chk, tuple(countIf(ext = ''), countIf(size = 0), countIf(startsWith(name, '~$') OR ext IN ('tmp','part'))) AS v FROM fileidx.files;
SELECT 'c1 archive: zip files / all files' AS chk, tuple(countIf(ext = 'zip'), count()) AS v FROM fileidx.files WHERE root = 'archive';
