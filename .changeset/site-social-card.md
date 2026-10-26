---
"@notch/web": patch
---

The site has a social card, and the tags that point at it.

og:image, twitter:image, og:type and og:site_name were all missing on the
home page. The card is drawn as the hero is drawn and generated once rather
than on every build.
