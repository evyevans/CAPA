# Mac notifications and inline replies

CAPA uses macOS local notifications while the companion remains running. Preferences → Enable notifications on this Mac requests permission and selects this paired installation as the workspace update destination. Focus and macOS notification settings can suppress banners. Send test notification verifies banner visibility without sending an agent task.

New Hermes response notifications preview the response and offer Reply through the notification options. A reply to a completed response submits a new contextual follow-up with its own persisted request ID. It does not mean an external action has succeeded. Formal approval and clarification events open task review; those events currently lack immutable control identity for safe inline answers.

Replies persist locally before networking. Unconfirmed follow-ups retain their request ID for retry in History. Only replies from the active device connection are displayed. A replacement pairing creates a new device identity, so old-device saved replies are not automatically replayed. Notification replies do not overwrite a recording or the main draft.

Acceptance check: enable notifications, move to another app, record “Reply exactly: CAPA notification test succeeded. Do not use tools.” Wait for the response notification, expand/options → Reply, send “Reply exactly: CAPA inline reply succeeded. Do not use tools.” Confirm the second response notification. Approval review can intentionally bring CAPA forward. No external messaging test is necessary.

Native release compilation and code review passed. Actual OS banner display and user typing into a notification still require the on-device acceptance check.

Preferences now refreshes macOS authorization and shows the selected delivery device. In Speak on selected device mode, new response events queue a banner as well as the existing spoken brief (first paragraph, up to 800 characters). Approvals and formal clarifications remain notification/review only. CAPA must remain running and the Mac awake; Focus and system alert style still control banner visibility.

Host verification on 2026-10-28: CAPA targets the unprefixed Hermes API at http://127.0.0.1:8642. Its API key matches the default ~/.hermes profile key (values were not displayed). The authenticated health endpoint returned the running gateway PID, and models advertised hermes-agent. Named desktop bots are separate conversations/profiles; connector authentication needs verification in the API session before using it for real actions.
