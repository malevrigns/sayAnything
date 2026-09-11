# Navigation and glass selectors

- Four equal primary tabs in this order: 动态 (feed), 聊天 (inbox), 附近 (embedded nearby), 我 (profile and owned/saved posts).
- Nearby in the main tab has no return arrow. Location stays opt-in; mounting the tab only reads server status.
- Tapping the dynamic page's top-left sayAnything logo/wordmark opens a separate settings route. That route and other pushed pages hide the bottom navigation. Brand has a real button accessibility role, minimum 48px height and constrained text width.
- Profile and settings are separate views of reusable controls. Nickname/gender and owned content live under 我; chat/display preferences live in 设置.
- Gender dialog uses transparent Material, 32px rounded strong Glass, and a horizontal segmented choice bar. Gender and font size share GlassChoiceBar so selected-pill styling stays identical.
- Keep all Go APIs and privacy/data behavior unchanged. Release is client patch 1.4.1+6, compatible with Go 1.4.
- Verify narrow-screen navigation/return behavior, the accessible settings entry, actual gender changes, and existing real chat/media/nearby flows. Screenshots remain local QA artifacts.
