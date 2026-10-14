# Fast navigation and focused nearby preview

- Cache only primary tabs that have been visited. Keep their state and scroll positions; paint only the active tab. Re-selecting the current tab is a no-op. An explicit new post can still invalidate/reload the feed.
- Bottom tabs switch immediately, with a short selection highlight. Subpages use a 160ms fade-through (outgoing fades before incoming), no horizontal move/zoom and no overlap of two live glass pages. Respect reduced motion.
- Cached pages observe PageActivity.isActiveOf(context), route visibility and app lifecycle. Pause inbox/chat polling while hidden; invalidate pending nearby positioning/navigation callbacks. Returning nearby refreshes status silently, never requests GPS automatically.
- Nearby's big consent card moves to a rounded glass Nearby settings popup opened by a toolbar button before Refresh. Main page emphasizes people and a compact sharing status. Existing consent, revision checks, expiry and hide behavior remain intact.
- Add explicitly labelled UI-only mock people for the Web preview build (PREVIEW_NEARBY=true). No mock users/coordinates are stored in Go. Mock greetings only explain that it is a preview. Real-list toggle remains available; native/default builds never show the demo list.
- Verify preserved feed request count/scroll state, hidden polling, pending GPS cancellation, reduced-motion route behavior, popup controls, demo labeling/no real greeting request, and normal API flows. Publish as client patch 1.4.2+7; backend stays unchanged.
