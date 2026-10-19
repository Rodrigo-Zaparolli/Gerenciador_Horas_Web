/// A new, manually confirmed hours selection releases prior unconfirmed items.
/// Confirmed items remain filtered by the integration ledger.
bool retryUnconfirmedHours({required String script, required bool sending}) =>
    sending && script == 'edesk_horas.py';
