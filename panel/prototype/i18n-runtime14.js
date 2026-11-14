"use strict";
// Runtime transport messages are resolved when reported, so language changes also affect pending requests.
I18N.add("zh", {
  "reason.readTimeout": "本地助手读取超时，请稍后重试。",
  "reason.submissionUnknown": "指令是否已被助手接收尚未确认。请查看操作记录和游戏画面，避免重复提交；助手不会自动重发。",
  "reason.statApplyAbort": "数值应用或还原未确认，召唤已停止，已生成单位保留。请先点「停止并清理」，再重新召唤。",
  "runtime14.httpRejected": "助手拒绝了此指令（HTTP {status}）。",
  "runtime14.commandLimit": "已有{n}条指令等待确认，请先等待结果。",
  "runtime14.poolsReadFailed": "怪物池读取失败",
  "runtime14.poolsSaveFailed": "怪物池保存失败",
  "runtime14.unitMissing": "当前目录找不到单位 {unit}，请检查目录或先从池里移除它。",
  "runtime14.catalogReadFailed": "单位目录读取失败"
});
I18N.add("en", {
  "reason.readTimeout": "Reading from the local assistant timed out. Try again shortly.",
  "reason.submissionUnknown": "It is not yet clear whether the assistant received this command. Check the operation history and the game before submitting it again. The assistant will not resend it automatically.",
  "reason.statApplyAbort": "The configured stats could not be safely applied or restored. Summoning was stopped and existing units were kept. Use Stop & clean up before summoning again.",
  "runtime14.httpRejected": "The assistant rejected this command (HTTP {status}).",
  "runtime14.commandLimit": "There are already {n} commands awaiting confirmation. Wait for their results.",
  "runtime14.poolsReadFailed": "Could not read the monster pools.",
  "runtime14.poolsSaveFailed": "Could not save the monster pools.",
  "runtime14.unitMissing": "The current catalog does not contain {unit}. Check the catalog or remove this entry from the pool.",
  "runtime14.catalogReadFailed": "Could not read the unit catalog."
});
I18N.add("ja", {
  "reason.readTimeout": "ローカルアシスタントの読み取りがタイムアウトしました。しばらくしてから再試行してください。",
  "reason.submissionUnknown": "コマンドをアシスタントが受信したか確認できません。再送する前に操作履歴とゲーム画面を確認してください。自動で再送されることはありません。",
  "reason.statApplyAbort": "設定したステータスの適用または復元を確認できなかったため、召喚を中止しました。生成済みのユニットは残っています。「停止して片付け」を押してから、もう一度召喚してください。",
  "runtime14.httpRejected": "アシスタントがコマンドを拒否しました（HTTP {status}）。",
  "runtime14.commandLimit": "確認待ちのコマンドが{n}件あります。結果を待ってから操作してください。",
  "runtime14.poolsReadFailed": "モンスタープールを読み取れませんでした。",
  "runtime14.poolsSaveFailed": "モンスタープールを保存できませんでした。",
  "runtime14.unitMissing": "現在のカタログに {unit} が見つかりません。カタログを確認するか、プールから削除してください。",
  "runtime14.catalogReadFailed": "ユニットカタログを読み取れませんでした。"
});
I18N.add("fr", {
  "reason.readTimeout": "La lecture depuis l’assistant local a expiré. Réessayez dans un instant.",
  "reason.submissionUnknown": "La réception de cette commande par l’assistant n’est pas confirmée. Consultez l’historique des opérations et le jeu avant de la soumettre à nouveau. Elle ne sera pas renvoyée automatiquement.",
  "reason.statApplyAbort": "L’application ou la restauration des statistiques configurées n’a pas pu être confirmée. L’invocation a été arrêtée et les unités déjà créées ont été conservées. Utilisez « Arrêter et nettoyer » avant d’invoquer à nouveau.",
  "runtime14.httpRejected": "L’assistant a refusé cette commande (HTTP {status}).",
  "runtime14.commandLimit": "{n} commandes sont déjà en attente de confirmation. Attendez leurs résultats.",
  "runtime14.poolsReadFailed": "Impossible de lire les réserves de monstres.",
  "runtime14.poolsSaveFailed": "Impossible d’enregistrer les réserves de monstres.",
  "runtime14.unitMissing": "Le catalogue actuel ne contient pas {unit}. Vérifiez le catalogue ou retirez cette entrée de la réserve.",
  "runtime14.catalogReadFailed": "Impossible de lire le catalogue des unités."
});
I18N.add("de", {
  "reason.readTimeout": "Zeitüberschreitung beim Lesen vom lokalen Assistenten. Bitte gleich erneut versuchen.",
  "reason.submissionUnknown": "Es ist noch unklar, ob der Assistent diesen Befehl empfangen hat. Prüfe den Aktionsverlauf und das Spiel, bevor du ihn erneut sendest. Er wird nicht automatisch erneut gesendet.",
  "reason.statApplyAbort": "Das Anwenden oder Wiederherstellen der eingestellten Werte konnte nicht bestätigt werden. Die Beschwörung wurde gestoppt; vorhandene Einheiten bleiben bestehen. Nutze „Stoppen & aufräumen“, bevor du erneut beschwörst.",
  "runtime14.httpRejected": "Der Assistent hat diesen Befehl abgelehnt (HTTP {status}).",
  "runtime14.commandLimit": "Für {n} Befehle steht die Bestätigung noch aus. Bitte auf die Ergebnisse warten.",
  "runtime14.poolsReadFailed": "Die Monsterpools konnten nicht gelesen werden.",
  "runtime14.poolsSaveFailed": "Die Monsterpools konnten nicht gespeichert werden.",
  "runtime14.unitMissing": "Der aktuelle Katalog enthält {unit} nicht. Prüfe den Katalog oder entferne diesen Eintrag aus dem Pool.",
  "runtime14.catalogReadFailed": "Der Einheitenkatalog konnte nicht gelesen werden."
});
I18N.add("es", {
  "reason.readTimeout": "Se agotó el tiempo de lectura del asistente local. Vuelve a intentarlo en un momento.",
  "reason.submissionUnknown": "No se ha confirmado si el asistente recibió esta orden. Revisa el historial de operaciones y el juego antes de volver a enviarla. No se reenviará automáticamente.",
  "reason.statApplyAbort": "No se pudo confirmar la aplicación o restauración de las estadísticas configuradas. Se detuvo la invocación y se conservaron las unidades creadas. Usa «Detener y limpiar» antes de volver a invocar.",
  "runtime14.httpRejected": "El asistente rechazó esta orden (HTTP {status}).",
  "runtime14.commandLimit": "Ya hay {n} órdenes pendientes de confirmación. Espera sus resultados.",
  "runtime14.poolsReadFailed": "No se pudieron leer los grupos de monstruos.",
  "runtime14.poolsSaveFailed": "No se pudieron guardar los grupos de monstruos.",
  "runtime14.unitMissing": "El catálogo actual no contiene {unit}. Comprueba el catálogo o elimina esta entrada del grupo.",
  "runtime14.catalogReadFailed": "No se pudo leer el catálogo de unidades."
});
if (typeof window !== "undefined") window.PG_I18N = I18N;
