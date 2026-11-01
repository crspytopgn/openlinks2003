# Fonts

`InterVariable.woff2` is Inter 4.1 by The Inter Project Authors
(https://github.com/rsms/inter), under the SIL Open Font License 1.1
(`Inter-LICENSE.txt`). It is cut down to Latin with fontTools:

```
pyftsubset InterVariable.woff2 --flavor=woff2 \
  --unicodes="U+0020-007E,U+00A0-00FF,U+0131,U+0152-0153,U+2013-2014,U+2018-201E,U+2022,U+2026,U+2032-2033,U+20AC,U+2122,U+2190-2193,U+2212" \
  --layout-features='kern,liga,calt,tnum,case'
```
