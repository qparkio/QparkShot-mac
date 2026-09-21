import SwiftUI

enum AppLanguage: String, CaseIterable, Codable, Identifiable {
  case english = "en"
  case spanish = "es"
  case chineseSimplified = "zh-Hans"
  case japanese = "ja"
  case french = "fr"
  case russian = "ru"
  case ukrainian = "uk"
  case kazakh = "kk"
  case arabic = "ar"
  case german = "de"
  case italian = "it"
  case portugueseBrazil = "pt-BR"

  var id: String { rawValue }

  var locale: Locale {
    Locale(identifier: rawValue)
  }

  var layoutDirection: LayoutDirection {
    self == .arabic ? .rightToLeft : .leftToRight
  }

  var visionRecognitionLanguage: String? {
    switch self {
    case .english: return "en-US"
    case .spanish: return "es-ES"
    case .chineseSimplified: return "zh-Hans"
    case .japanese: return "ja-JP"
    case .french: return "fr-FR"
    case .russian: return "ru-RU"
    case .ukrainian: return "uk-UA"
    case .kazakh: return nil
    case .arabic: return "ar-SA"
    case .german: return "de-DE"
    case .italian: return "it-IT"
    case .portugueseBrazil: return "pt-BR"
    }
  }

  func displayName(in language: AppLanguage) -> String {
    let displayLocale = Locale(identifier: language.rawValue)
    return displayLocale.localizedString(forIdentifier: rawValue) ?? rawValue
  }

  static func preferredDefault(from preferredLanguages: [String] = Locale.preferredLanguages) -> AppLanguage {
    for identifier in preferredLanguages {
      if let exact = AppLanguage(rawValue: identifier) {
        return exact
      }

      let prefix = identifier.split(separator: "-").first.map(String.init) ?? identifier
      if let prefixMatch = AppLanguage.allCases.first(where: { $0.rawValue == prefix }) {
        return prefixMatch
      }

      if identifier.hasPrefix("zh") {
        return .chineseSimplified
      }
      if identifier.hasPrefix("pt") {
        return .portugueseBrazil
      }
    }
    return .english
  }
}

struct LocalizationSettings: Codable, Equatable {
  var appLanguageCode: String
  var textRecognitionLanguageCodes: [String]

  init(
    appLanguageCode: String = AppLanguage.preferredDefault().rawValue,
    textRecognitionLanguageCodes: [String] = [AppLanguage.preferredDefault().rawValue, AppLanguage.english.rawValue]
  ) {
    self.appLanguageCode = AppLanguage(rawValue: appLanguageCode)?.rawValue ?? AppLanguage.english.rawValue
    var seen = Set<String>()
    self.textRecognitionLanguageCodes = textRecognitionLanguageCodes.compactMap { code in
      guard let language = AppLanguage(rawValue: code), !seen.contains(language.rawValue) else {
        return nil
      }
      seen.insert(language.rawValue)
      return language.rawValue
    }
    if self.textRecognitionLanguageCodes.isEmpty {
      self.textRecognitionLanguageCodes = [AppLanguage.english.rawValue]
    }
  }

  init(from decoder: Decoder) throws {
    let defaults = LocalizationSettings()
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let language = try container.decodeIfPresent(String.self, forKey: .appLanguageCode) ?? defaults.appLanguageCode
    let recognition = try container.decodeIfPresent([String].self, forKey: .textRecognitionLanguageCodes)
      ?? defaults.textRecognitionLanguageCodes
    self.init(appLanguageCode: language, textRecognitionLanguageCodes: recognition)
  }
}

final class LocalizationController: ObservableObject {
  static let shared = LocalizationController()

  @Published private(set) var language: AppLanguage

  private init(settings: SettingsStore = .shared) {
    language = AppLanguage(rawValue: settings.appLanguageCode) ?? .english
  }

  var locale: Locale { language.locale }
  var layoutDirection: LayoutDirection { language.layoutDirection }

  func refreshFromSettings() {
    let next = AppLanguage(rawValue: SettingsStore.shared.appLanguageCode) ?? .english
    if next != language {
      language = next
    }
  }

  @MainActor
  func setLanguage(_ next: AppLanguage) {
    guard next != language else { return }
    SettingsStore.shared.appLanguageCode = next.rawValue
    SettingsStore.shared.save()
    language = next
    AppDelegate.current?.rebuildLocalizedSurfaces()
  }

  func text(_ key: String) -> String {
    let table = Self.translations[key] ?? [:]
    return table[language] ?? table[.english] ?? key
  }

  func format(_ key: String, _ values: CVarArg...) -> String {
    String(format: text(key), locale: locale, arguments: values)
  }

  static let requiredKeys: [String] = Array(translations.keys).sorted()

  static func hasTranslation(for key: String, language: AppLanguage) -> Bool {
    translations[key]?[language] != nil
  }

  private static let translations: [String: [AppLanguage: String]] = {
    func row(
      _ en: String,
      _ es: String,
      _ zh: String,
      _ ja: String,
      _ fr: String,
      _ ru: String,
      _ uk: String,
      _ kk: String,
      _ ar: String,
      _ de: String,
      _ it: String,
      _ pt: String
    ) -> [AppLanguage: String] {
      [
        .english: en,
        .spanish: es,
        .chineseSimplified: zh,
        .japanese: ja,
        .french: fr,
        .russian: ru,
        .ukrainian: uk,
        .kazakh: kk,
        .arabic: ar,
        .german: de,
        .italian: it,
        .portugueseBrazil: pt
      ]
    }

    return [
      "app.name": row("QPARK Shot", "QPARK Shot", "QPARK Shot", "QPARK Shot", "QPARK Shot", "QPARK Shot", "QPARK Shot", "QPARK Shot", "QPARK Shot", "QPARK Shot", "QPARK Shot", "QPARK Shot"),
      "common.done": row("Done", "Listo", "完成", "完了", "Terminé", "Готово", "Готово", "Дайын", "تم", "Fertig", "Fine", "Concluído"),
      "common.cancel": row("Cancel", "Cancelar", "取消", "キャンセル", "Annuler", "Отмена", "Скасувати", "Бас тарту", "إلغاء", "Abbrechen", "Annulla", "Cancelar"),
      "common.clear": row("Clear", "Limpiar", "清除", "クリア", "Effacer", "Очистить", "Очистити", "Тазалау", "مسح", "Leeren", "Cancella", "Limpar"),
      "common.delete": row("Delete", "Eliminar", "删除", "削除", "Supprimer", "Удалить", "Видалити", "Жою", "حذف", "Löschen", "Elimina", "Excluir"),
      "common.move_to_trash": row("Move to Trash", "Mover a la papelera", "移到废纸篓", "ゴミ箱に移動", "Placer dans la corbeille", "Переместить в Корзину", "Перемістити в Смітник", "Себетке жылжыту", "نقل إلى سلة المهملات", "In den Papierkorb", "Sposta nel Cestino", "Mover para o Lixo"),
      "common.locate": row("Locate…", "Localizar…", "查找…", "場所を指定…", "Localiser…", "Найти…", "Знайти…", "Табу…", "تحديد الموقع…", "Suchen…", "Individua…", "Localizar…"),
      "common.forget": row("Forget", "Olvidar", "忽略", "登録を解除", "Oublier", "Забыть", "Забути", "Ұмыту", "نسيان", "Vergessen", "Dimentica", "Esquecer"),
      "common.edit": row("Edit", "Editar", "编辑", "編集", "Modifier", "Редактировать", "Редагувати", "Өңдеу", "تحرير", "Bearbeiten", "Modifica", "Editar"),
      "common.copy": row("Copy", "Copiar", "复制", "コピー", "Copier", "Копировать", "Копіювати", "Көшіру", "نسخ", "Kopieren", "Copia", "Copiar"),
      "common.save": row("Save", "Guardar", "保存", "保存", "Enregistrer", "Сохранить", "Зберегти", "Сақтау", "حفظ", "Sichern", "Salva", "Salvar"),
      "common.share": row("Share", "Compartir", "共享", "共有", "Partager", "Поделиться", "Поділитися", "Бөлісу", "مشاركة", "Teilen", "Condividi", "Compartilhar"),
      "common.pin": row("Pin", "Fijar", "置顶", "ピン留め", "Épingler", "Закрепить", "Закріпити", "Бекіту", "تثبيت", "Anheften", "Fissa", "Fixar"),
      "common.open": row("Open", "Abrir", "打开", "開く", "Ouvrir", "Открыть", "Відкрити", "Ашу", "فتح", "Öffnen", "Apri", "Abrir"),
      "common.preview": row("Preview", "Vista previa", "预览", "プレビュー", "Aperçu", "Просмотр", "Перегляд", "Алдын ала қарау", "معاينة", "Vorschau", "Anteprima", "Prévia"),
      "common.search": row("Search", "Buscar", "搜索", "検索", "Rechercher", "Поиск", "Пошук", "Іздеу", "بحث", "Suchen", "Cerca", "Buscar"),
      "common.settings": row("Settings", "Configuración", "设置", "設定", "Réglages", "Настройки", "Налаштування", "Параметрлер", "الإعدادات", "Einstellungen", "Impostazioni", "Ajustes"),
      "common.preferences": row("Settings…", "Configuración…", "设置…", "設定…", "Réglages…", "Настройки…", "Налаштування…", "Параметрлер…", "الإعدادات…", "Einstellungen…", "Impostazioni…", "Ajustes…"),
      "common.quit": row("Quit QPARK Shot", "Salir de QPARK Shot", "退出 QPARK Shot", "QPARK Shot を終了", "Quitter QPARK Shot", "Выйти из QPARK Shot", "Вийти з QPARK Shot", "QPARK Shot қолданбасынан шығу", "إنهاء QPARK Shot", "QPARK Shot beenden", "Esci da QPARK Shot", "Sair do QPARK Shot"),
      "common.close": row("Close", "Cerrar", "关闭", "閉じる", "Fermer", "Закрыть", "Закрити", "Жабу", "إغلاق", "Schließen", "Chiudi", "Fechar"),
      "common.back": row("Back", "Atrás", "返回", "戻る", "Retour", "Назад", "Назад", "Артқа", "رجوع", "Zurück", "Indietro", "Voltar"),
      "common.favorite": row("Favorite", "Favorito", "收藏", "お気に入り", "Favori", "В избранное", "Вибране", "Таңдаулы", "مفضلة", "Favorit", "Preferito", "Favorito"),
      "common.remove_favorite": row("Remove Favorite", "Quitar favorito", "取消收藏", "お気に入りから削除", "Retirer des favoris", "Убрать из избранного", "Прибрати з вибраного", "Таңдаулыдан алу", "إزالة من المفضلة", "Favorit entfernen", "Rimuovi preferito", "Remover favorito"),
      "common.show_in_finder": row("Show in Finder", "Mostrar en Finder", "在 Finder 中显示", "Finder に表示", "Afficher dans le Finder", "Показать в Finder", "Показати у Finder", "Finder ішінде көрсету", "إظهار في Finder", "Im Finder zeigen", "Mostra nel Finder", "Mostrar no Finder"),
      "common.more": row("More", "Más", "更多", "その他", "Plus", "Ещё", "Ще", "Тағы", "المزيد", "Mehr", "Altro", "Mais"),
      "menu.capture": row("Capture", "Capturar", "截图", "キャプチャ", "Capture", "Снимок", "Знімок", "Түсіру", "التقاط", "Aufnehmen", "Acquisisci", "Capturar"),
      "menu.view": row("View", "Vista", "视图", "表示", "Présentation", "Вид", "Вигляд", "Көрініс", "عرض", "Darstellung", "Vista", "Visualizar"),
      "menu.tools": row("Tools", "Herramientas", "工具", "ツール", "Outils", "Инструменты", "Інструменти", "Құралдар", "الأدوات", "Werkzeuge", "Strumenti", "Ferramentas"),
      "settings.about": row("About", "Acerca de", "关于", "このアプリについて", "À propos", "О приложении", "Про застосунок", "Қолданба туралы", "حول التطبيق", "Über die App", "Informazioni", "Sobre"),
      "settings.version": row("Version", "Versión", "版本", "バージョン", "Version", "Версия", "Версія", "Нұсқа", "الإصدار", "Version", "Versione", "Versão"),
      "menu.about": row("About QPARK Shot", "Acerca de QPARK Shot", "关于 QPARK Shot", "QPARK Shot について", "À propos de QPARK Shot", "О QPARK Shot", "Про QPARK Shot", "QPARK Shot туралы", "حول QPARK Shot", "Über QPARK Shot", "Informazioni su QPARK Shot", "Sobre o QPARK Shot"),
      "menu.hide": row("Hide QPARK Shot", "Ocultar QPARK Shot", "隐藏 QPARK Shot", "QPARK Shot を非表示", "Masquer QPARK Shot", "Скрыть QPARK Shot", "Сховати QPARK Shot", "QPARK Shot жасыру", "إخفاء QPARK Shot", "QPARK Shot ausblenden", "Nascondi QPARK Shot", "Ocultar QPARK Shot"),
      "menu.edit": row("Edit", "Edición", "编辑", "編集", "Édition", "Правка", "Редагування", "Өңдеу", "تحرير", "Bearbeiten", "Modifica", "Editar"),
      "menu.cut": row("Cut", "Cortar", "剪切", "カット", "Couper", "Вырезать", "Вирізати", "Қиып алу", "قص", "Ausschneiden", "Taglia", "Recortar"),
      "menu.paste": row("Paste", "Pegar", "粘贴", "ペースト", "Coller", "Вставить", "Вставити", "Қою", "لصق", "Einsetzen", "Incolla", "Colar"),
      "menu.select_all": row("Select All", "Seleccionar todo", "全选", "すべてを選択", "Tout sélectionner", "Выбрать всё", "Вибрати все", "Барлығын таңдау", "تحديد الكل", "Alles auswählen", "Seleziona tutto", "Selecionar tudo"),
      "menu.window": row("Window", "Ventana", "窗口", "ウインドウ", "Fenêtre", "Окно", "Вікно", "Терезе", "النافذة", "Fenster", "Finestra", "Janela"),
      "menu.minimize": row("Minimize", "Minimizar", "最小化", "しまう", "Réduire", "Свернуть", "Згорнути", "Кішірейту", "تصغير", "Minimieren", "Contrai", "Minimizar"),
      "capture.selected_area": row("Capture Selected Area", "Capturar área seleccionada", "截取所选区域", "選択範囲をキャプチャ", "Capturer la zone sélectionnée", "Снять выбранную область", "Зняти вибрану область", "Таңдалған аймақты түсіру", "التقاط منطقة محددة", "Ausgewählten Bereich aufnehmen", "Acquisisci area selezionata", "Capturar área selecionada"),
      "capture.full_screen": row("Capture Full Screen", "Capturar pantalla completa", "截取全屏", "フルスクリーンをキャプチャ", "Capturer tout l’écran", "Снять весь экран", "Зняти весь екран", "Толық экранды түсіру", "التقاط الشاشة كاملة", "Vollbild aufnehmen", "Acquisisci schermo intero", "Capturar tela inteira"),
      "capture.window": row("Capture Window", "Capturar ventana", "截取窗口", "ウインドウをキャプチャ", "Capturer une fenêtre", "Снять окно", "Зняти вікно", "Терезені түсіру", "التقاط نافذة", "Fenster aufnehmen", "Acquisisci finestra", "Capturar janela"),
      "capture.repeat_area": row("Repeat Last Area", "Repetir última área", "重复上次区域", "最後の範囲を繰り返す", "Répéter la dernière zone", "Повторить область", "Повторити область", "Соңғы аймақты қайталау", "تكرار آخر منطقة", "Letzten Bereich wiederholen", "Ripeti ultima area", "Repetir última área"),
      "capture.with_delay": row("Capture with Delay", "Capturar con retraso", "延时截图", "遅延キャプチャ", "Capture différée", "Снимок с задержкой", "Знімок із затримкою", "Кідіріс арқылы түсіру", "التقاط مع تأخير", "Aufnahme mit Verzögerung", "Acquisisci con ritardo", "Capturar com atraso"),
      "capture.seconds_format": row("%d seconds", "%d segundos", "%d 秒", "%d 秒", "%d secondes", "%d сек.", "%d с", "%d с", "%d ثوان", "%d Sekunden", "%d secondi", "%d segundos"),
      "workspace.library": row("Library", "Biblioteca", "图库", "ライブラリ", "Bibliothèque", "Библиотека", "Бібліотека", "Кітапхана", "المكتبة", "Mediathek", "Libreria", "Biblioteca"),
      "workspace.current_session": row("Current Session", "Sesión actual", "当前会话", "現在のセッション", "Session actuelle", "Текущая сессия", "Поточна сесія", "Ағымдағы сессия", "الجلسة الحالية", "Aktuelle Sitzung", "Sessione corrente", "Sessão atual"),
      "workspace.favorites": row("Favorites", "Favoritos", "收藏", "お気に入り", "Favoris", "Избранное", "Вибране", "Таңдаулылар", "المفضلة", "Favoriten", "Preferiti", "Favoritos"),
      "workspace.recent": row("Recent", "Recientes", "最近", "最近", "Récents", "Недавние", "Нещодавні", "Соңғылар", "الأخيرة", "Zuletzt", "Recenti", "Recentes"),
      "workspace.missing": row("Missing", "No encontrados", "缺失", "見つかりません", "Manquants", "Потеряно", "Відсутні", "Жоқ", "مفقودة", "Fehlend", "Mancanti", "Ausentes"),
      "workspace.search_placeholder": row("Search screenshots, tags, OCR text", "Buscar capturas, etiquetas, texto OCR", "搜索截图、标签、OCR 文本", "スクリーンショット、タグ、OCR テキストを検索", "Rechercher captures, tags, texte OCR", "Искать снимки, теги и OCR-текст", "Шукати знімки, теги й OCR-текст", "Скриншоттарды, тегтерді, OCR мәтінін іздеу", "البحث في اللقطات والوسوم ونص OCR", "Screenshots, Tags und OCR-Text suchen", "Cerca screenshot, tag e testo OCR", "Buscar capturas, tags e texto OCR"),
      "workspace.no_shots": row("No screenshots yet.", "Aún no hay capturas.", "还没有截图。", "まだスクリーンショットはありません。", "Aucune capture pour le moment.", "Снимков пока нет.", "Знімків ще немає.", "Әзірге скриншот жоқ.", "لا توجد لقطات بعد.", "Noch keine Screenshots.", "Nessuno screenshot.", "Ainda não há capturas."),
      "workspace.no_matches": row("No matching screenshots.", "No hay capturas coincidentes.", "没有匹配的截图。", "一致するスクリーンショットはありません。", "Aucune capture correspondante.", "Нет совпадающих снимков.", "Немає відповідних знімків.", "Сәйкес скриншот жоқ.", "لا توجد لقطات مطابقة.", "Keine passenden Screenshots.", "Nessuno screenshot corrispondente.", "Nenhuma captura encontrada."),
      "workspace.capture_cta": row("Capture", "Capturar", "截图", "キャプチャ", "Capturer", "Снять", "Зняти", "Түсіру", "التقاط", "Aufnehmen", "Acquisisci", "Capturar"),
      "workspace.clear_session": row("Clear Session", "Limpiar sesión", "清除会话", "セッションをクリア", "Effacer la session", "Очистить сессию", "Очистити сесію", "Сессияны тазалау", "مسح الجلسة", "Sitzung leeren", "Cancella sessione", "Limpar sessão"),
      "workspace.empty_session": row("No captures in the current session.", "No hay capturas en la sesión actual.", "当前会话中没有截图。", "現在のセッションにキャプチャはありません。", "Aucune capture dans la session actuelle.", "В текущей сессии нет снимков.", "У поточній сесії немає знімків.", "Ағымдағы сессияда түсірілім жоқ.", "لا توجد لقطات في الجلسة الحالية.", "Keine Aufnahmen in der aktuellen Sitzung.", "Nessuna acquisizione nella sessione corrente.", "Sem capturas na sessão atual."),
      "workspace.no_recent": row("No screenshots from the last 7 days.", "No hay capturas de los últimos 7 días.", "最近 7 天没有截图。", "過去7日間のスクリーンショットはありません。", "Aucune capture des 7 derniers jours.", "Нет снимков за последние 7 дней.", "Немає знімків за останні 7 днів.", "Соңғы 7 күнде скриншот жоқ.", "لا توجد لقطات خلال آخر 7 أيام.", "Keine Screenshots aus den letzten 7 Tagen.", "Nessuno screenshot degli ultimi 7 giorni.", "Nenhuma captura dos últimos 7 dias."),
      "workspace.no_missing": row("No missing screenshots.", "No faltan capturas.", "没有丢失的截图。", "見つからないスクリーンショットはありません。", "Aucune capture manquante.", "Потерянных снимков нет.", "Відсутніх знімків немає.", "Жоғалған скриншот жоқ.", "لا توجد لقطات مفقودة.", "Keine fehlenden Screenshots.", "Nessuno screenshot mancante.", "Nenhuma captura ausente."),
      "workspace.missing_hint": row("Locate the moved file or forget its saved metadata.", "Localiza el archivo movido u olvida sus metadatos.", "查找已移动的文件，或忽略其保存的元数据。", "移動したファイルを指定するか、保存済みメタデータを解除します。", "Localisez le fichier déplacé ou oubliez ses métadonnées.", "Найдите перемещённый файл или удалите его метаданные.", "Знайдіть переміщений файл або видаліть його метадані.", "Жылжытылған файлды табыңыз немесе метадеректерін ұмытыңыз.", "حدد الملف المنقول أو انس بياناته الوصفية.", "Verschobene Datei suchen oder Metadaten vergessen.", "Individua il file spostato o dimentica i metadati.", "Localize o arquivo movido ou esqueça os metadados."),
      "workspace.clear_session_title": row("Clear Current Session?", "¿Limpiar la sesión actual?", "清除当前会话？", "現在のセッションを消去しますか？", "Effacer la session actuelle ?", "Очистить текущую сессию?", "Очистити поточну сесію?", "Ағымдағы сессия тазалансын ба?", "مسح الجلسة الحالية؟", "Aktuelle Sitzung leeren?", "Cancellare la sessione corrente?", "Limpar a sessão atual?"),
      "workspace.clear_session_message": row("Temporary captures and unsaved edits will be removed.", "Se eliminarán las capturas temporales y los cambios sin guardar.", "临时截图和未保存的编辑将被移除。", "一時キャプチャと未保存の編集内容が削除されます。", "Les captures temporaires et modifications non enregistrées seront supprimées.", "Временные снимки и несохранённые правки будут удалены.", "Тимчасові знімки й незбережені зміни буде видалено.", "Уақытша суреттер мен сақталмаған өзгерістер жойылады.", "ستُحذف اللقطات المؤقتة والتعديلات غير المحفوظة.", "Temporäre Aufnahmen und ungesicherte Änderungen werden entfernt.", "Le acquisizioni temporanee e le modifiche non salvate verranno eliminate.", "Capturas temporárias e edições não salvas serão removidas."),
      "workspace.clear_session_count": row("Temporary captures to remove: %d.", "Capturas temporales que se eliminarán: %d.", "将移除的临时截图：%d。", "削除する一時キャプチャ：%d。", "Captures temporaires à supprimer : %d.", "Временных снимков к удалению: %d.", "Тимчасових знімків до видалення: %d.", "Жойылатын уақытша суреттер: %d.", "اللقطات المؤقتة المراد حذفها: %d.", "Zu entfernende temporäre Aufnahmen: %d.", "Acquisizioni temporanee da rimuovere: %d.", "Capturas temporárias a remover: %d."),
      "workspace.unsaved_draft_warning": row("Unsaved edits will also be lost.", "También se perderán los cambios no guardados.", "未保存的编辑也会丢失。", "未保存の編集内容も失われます。", "Les modifications non enregistrées seront aussi perdues.", "Несохранённые правки также будут потеряны.", "Незбережені правки також буде втрачено.", "Сақталмаған өзгерістер де жоғалады.", "ستُفقد التعديلات غير المحفوظة أيضًا.", "Ungesicherte Änderungen gehen ebenfalls verloren.", "Anche le modifiche non salvate andranno perse.", "As edições não salvas também serão perdidas."),
      "workspace.inspector": row("Inspector", "Inspector", "检查器", "インスペクタ", "Inspecteur", "Инспектор", "Інспектор", "Инспектор", "المفتش", "Inspektor", "Ispettore", "Inspetor"),
      "inspector.ocr": row("OCR Text", "Texto OCR", "OCR 文本", "OCR テキスト", "Texte OCR", "OCR-текст", "OCR-текст", "OCR мәтіні", "نص OCR", "OCR-Text", "Testo OCR", "Texto OCR"),
      "inspector.tags": row("Tags", "Etiquetas", "标签", "タグ", "Tags", "Теги", "Теги", "Тегтер", "الوسوم", "Tags", "Tag", "Tags"),
      "inspector.tags_hint": row("Comma-separated", "Separadas por comas", "用逗号分隔", "カンマ区切り", "Séparés par des virgules", "Через запятую", "Через кому", "Үтір арқылы", "مفصولة بفواصل", "Durch Kommas getrennt", "Separati da virgole", "Separadas por vírgulas"),
      "common.retry": row("Retry", "Reintentar", "重试", "再試行", "Réessayer", "Повторить", "Повторити", "Қайталау", "إعادة المحاولة", "Erneut versuchen", "Riprova", "Tentar novamente"),
      "workspace.no_selection": row("No selection.", "Sin selección.", "未选择。", "選択なし。", "Aucune sélection.", "Ничего не выбрано.", "Нічого не вибрано.", "Таңдалмаған.", "لا يوجد تحديد.", "Keine Auswahl.", "Nessuna selezione.", "Nada selecionado."),
      "review.captured": row("Captured", "Capturado", "已截图", "キャプチャ済み", "Capturé", "Снято", "Знято", "Түсірілді", "تم الالتقاط", "Aufgenommen", "Acquisito", "Capturado"),
      "review.saved": row("Saved to Library.", "Guardado en la biblioteca.", "已保存到图库。", "ライブラリに保存しました。", "Enregistré dans la bibliothèque.", "Сохранено в библиотеку.", "Збережено в бібліотеку.", "Кітапханаға сақталды.", "تم الحفظ في المكتبة.", "In Mediathek gesichert.", "Salvato nella libreria.", "Salvo na biblioteca."),
      "review.copied": row("Copied final image.", "Imagen final copiada.", "已复制最终图像。", "最終画像をコピーしました。", "Image finale copiée.", "Финальное изображение скопировано.", "Фінальне зображення скопійовано.", "Соңғы сурет көшірілді.", "تم نسخ الصورة النهائية.", "Finales Bild kopiert.", "Immagine finale copiata.", "Imagem final copiada."),
      "review.pinned": row("Pinned on screen.", "Fijado en pantalla.", "已固定在屏幕上。", "画面にピン留めしました。", "Épinglé à l’écran.", "Закреплено на экране.", "Закріплено на екрані.", "Экранға бекітілді.", "تم التثبيت على الشاشة.", "Auf Bildschirm angeheftet.", "Fissato sullo schermo.", "Fixado na tela."),
      "review.save_failed": row("Save failed.", "No se pudo guardar.", "保存失败。", "保存に失敗しました。", "Échec de l’enregistrement.", "Не удалось сохранить.", "Не вдалося зберегти.", "Сақтау сәтсіз.", "فشل الحفظ.", "Sichern fehlgeschlagen.", "Salvataggio non riuscito.", "Falha ao salvar."),
      "editor.back": row("Back to Library", "Volver a la biblioteca", "返回图库", "ライブラリに戻る", "Retour à la bibliothèque", "Назад в библиотеку", "Назад до бібліотеки", "Кітапханаға қайту", "العودة إلى المكتبة", "Zurück zur Mediathek", "Torna alla libreria", "Voltar à biblioteca"),
      "editor.tools": row("Tools", "Herramientas", "工具", "ツール", "Outils", "Инструменты", "Інструменти", "Құралдар", "الأدوات", "Werkzeuge", "Strumenti", "Ferramentas"),
      "editor.undo": row("Undo", "Deshacer", "撤销", "取り消す", "Annuler", "Отменить", "Скасувати", "Болдырмау", "تراجع", "Widerrufen", "Annulla", "Desfazer"),
      "editor.redo": row("Redo", "Rehacer", "重做", "やり直す", "Rétablir", "Повторить", "Повторити", "Қайталау", "إعادة", "Wiederholen", "Ripeti", "Refazer"),
      "editor.color": row("Color", "Color", "颜色", "カラー", "Couleur", "Цвет", "Колір", "Түс", "اللون", "Farbe", "Colore", "Cor"),
      "editor.stroke": row("Stroke", "Trazo", "线条", "線", "Trait", "Линия", "Лінія", "Сызық", "الخط", "Strich", "Tratto", "Traço"),
      "editor.text_placeholder": row("Text", "Texto", "文本", "テキスト", "Texte", "Текст", "Текст", "Мәтін", "نص", "Text", "Testo", "Texto"),
      "editor.clear_crop": row("Clear Crop", "Quitar recorte", "清除裁剪", "クロップを解除", "Effacer le recadrage", "Очистить кроп", "Очистити обрізання", "Қиюды тазалау", "مسح القص", "Zuschnitt löschen", "Cancella ritaglio", "Limpar corte"),
      "editor.tool_arrow": row("Arrow", "Flecha", "箭头", "矢印", "Flèche", "Стрелка", "Стрілка", "Көрсеткі", "سهم", "Pfeil", "Freccia", "Seta"),
      "editor.tool_rectangle": row("Rectangle", "Rectángulo", "矩形", "長方形", "Rectangle", "Прямоугольник", "Прямокутник", "Тіктөртбұрыш", "مستطيل", "Rechteck", "Rettangolo", "Retângulo"),
      "editor.tool_freehand": row("Freehand", "Mano alzada", "手绘", "フリーハンド", "Main levée", "От руки", "Від руки", "Қолмен", "رسم حر", "Freihand", "Mano libera", "Livre"),
      "editor.tool_text": row("Text", "Texto", "文本", "テキスト", "Texte", "Текст", "Текст", "Мәтін", "نص", "Text", "Testo", "Texto"),
      "editor.tool_callout": row("Callout", "Llamada", "标注", "吹き出し", "Repère", "Выноска", "Виноска", "Белгі", "وسم", "Hinweis", "Richiamo", "Chamada"),
      "editor.tool_redact": row("Redact", "Ocultar", "遮盖", "墨消し", "Masquer", "Скрыть", "Приховати", "Жасыру", "تنقيح", "Schwärzen", "Oscura", "Ocultar"),
      "editor.tool_blur": row("Blur", "Difuminar", "模糊", "ぼかし", "Flou", "Размытие", "Розмиття", "Бұлыңғыр", "تمويه", "Weichzeichnen", "Sfoca", "Desfocar"),
      "editor.tool_crop": row("Crop", "Recortar", "裁剪", "切り抜き", "Recadrer", "Кадрировать", "Обрізати", "Қию", "قص", "Zuschneiden", "Ritaglia", "Cortar"),
      "editor.preview_watermarks": row("Preview with Watermarks", "Vista previa con marcas", "预览水印", "透かし付きプレビュー", "Aperçu avec filigranes", "Просмотр с водяными знаками", "Перегляд із водяними знаками", "Су таңбасымен алдын ала қарау", "معاينة مع العلامات المائية", "Vorschau mit Wasserzeichen", "Anteprima con filigrane", "Prévia com marcas d’água"),
      "editor.exporting": row("Exporting", "Exportando", "正在导出", "書き出し中", "Exportation", "Экспорт", "Експорт", "Экспортталуда", "جارٍ التصدير", "Exportieren", "Esportazione", "Exportando"),
      "editor.saved": row("Saved final image.", "Imagen final guardada.", "最终图像已保存。", "最終画像を保存しました。", "Image finale enregistrée.", "Финальное изображение сохранено.", "Фінальне зображення збережено.", "Соңғы сурет сақталды.", "تم حفظ الصورة النهائية.", "Finales Bild gesichert.", "Immagine finale salvata.", "Imagem final salva."),
      "settings.general": row("General", "General", "通用", "一般", "Général", "Основные", "Загальні", "Жалпы", "عام", "Allgemein", "Generali", "Geral"),
      "settings.subtitle.general": row("Language, appearance and local intelligence.", "Idioma, apariencia e inteligencia local.", "语言、外观和本地智能。", "言語、外観、ローカル機能。", "Langue, apparence et intelligence locale.", "Язык, оформление и локальные функции.", "Мова, вигляд і локальні функції.", "Тіл, көрініс және жергілікті мүмкіндіктер.", "اللغة والمظهر والذكاء المحلي.", "Sprache, Darstellung und lokale Intelligenz.", "Lingua, aspetto e funzioni locali.", "Idioma, aparência e recursos locais."),
      "settings.language": row("Language", "Idioma", "语言", "言語", "Langue", "Язык", "Мова", "Тіл", "اللغة", "Sprache", "Lingua", "Idioma"),
      "settings.appearance": row("Appearance", "Apariencia", "外观", "外観", "Apparence", "Оформление", "Вигляд", "Көрініс", "المظهر", "Erscheinungsbild", "Aspetto", "Aparência"),
      "settings.capture": row("Capture", "Captura", "截图", "キャプチャ", "Capture", "Снимок", "Знімок", "Түсіру", "التقاط", "Aufnahme", "Acquisizione", "Captura"),
      "settings.subtitle.capture": row("Choose capture behavior and the default review flow.", "Elige el comportamiento de captura y la revisión.", "选择截图行为和默认回顾流程。", "キャプチャ動作と確認フローを選択します。", "Choisissez la capture et le flux de revue.", "Поведение снимка и обзор после захвата.", "Поведінка знімка й огляд після захоплення.", "Түсіру әрекеті және кейінгі шолу.", "اختر سلوك الالتقاط وتدفق المراجعة.", "Aufnahmeverhalten und Prüfablauf wählen.", "Scegli acquisizione e revisione.", "Escolha captura e revisão padrão."),
      "settings.export": row("Export", "Exportar", "导出", "書き出し", "Export", "Экспорт", "Експорт", "Экспорт", "تصدير", "Export", "Esporta", "Exportar"),
      "settings.subtitle.export": row("Presets and filenames for saved output.", "Preajustes y nombres para archivos guardados.", "保存输出的预设和文件名。", "保存出力のプリセットと名前。", "Préréglages et noms des fichiers.", "Пресеты и имена сохраняемых файлов.", "Пресети й назви збережених файлів.", "Сақталған файл пресеттері мен атаулары.", "إعدادات وأسماء الملفات المحفوظة.", "Vorgaben und Dateinamen für Exporte.", "Predefiniti e nomi dei file.", "Predefinições e nomes dos arquivos."),
      "settings.watermark": row("Watermark", "Marca de agua", "水印", "透かし", "Filigrane", "Водяной знак", "Водяний знак", "Су таңбасы", "علامة مائية", "Wasserzeichen", "Filigrana", "Marca d’água"),
      "settings.subtitle.watermark": row("Preview and tune the mark before export.", "Previsualiza y ajusta la marca antes de exportar.", "导出前预览并调整水印。", "書き出し前に透かしを確認して調整します。", "Prévisualisez et ajustez le filigrane.", "Просмотр и настройка перед экспортом.", "Перегляд і налаштування перед експортом.", "Экспорт алдында су таңбасын көру.", "عاين واضبط العلامة قبل التصدير.", "Wasserzeichen vor Export prüfen.", "Anteprima e regolazione filigrana.", "Prévia e ajuste da marca."),
      "settings.storage": row("Storage", "Almacenamiento", "存储", "ストレージ", "Stockage", "Хранилище", "Сховище", "Сақтау орны", "التخزين", "Speicher", "Archiviazione", "Armazenamento"),
      "settings.subtitle.storage": row("Library location, cleanup and retained files.", "Ubicación, limpieza y archivos guardados.", "图库位置、清理和保留文件。", "ライブラリ場所、クリーンアップ、保持ファイル。", "Emplacement, nettoyage et fichiers conservés.", "Папка библиотеки, очистка и файлы.", "Папка бібліотеки, очищення й файли.", "Кітапхана орны, тазалау және файлдар.", "موقع المكتبة والتنظيف والملفات.", "Mediathekort, Bereinigung und Dateien.", "Posizione, pulizia e file conservati.", "Local, limpeza e arquivos mantidos."),
      "settings.index": row("Library Index", "Índice de biblioteca", "图库索引", "ライブラリ索引", "Index de bibliothèque", "Индекс библиотеки", "Індекс бібліотеки", "Кітапхана индексі", "فهرس المكتبة", "Mediathekindex", "Indice libreria", "Índice da biblioteca"),
      "settings.ocr_languages": row("Text Recognition Languages", "Idiomas de reconocimiento de texto", "文本识别语言", "テキスト認識言語", "Langues de reconnaissance de texte", "Языки распознавания текста", "Мови розпізнавання тексту", "Мәтінді тану тілдері", "لغات التعرف على النص", "Sprachen für Texterkennung", "Lingue riconoscimento testo", "Idiomas de reconhecimento de texto"),
      "settings.after_capture": row("After Capture", "Después de capturar", "截图后", "キャプチャ後", "Après la capture", "После снимка", "Після знімка", "Түсіргеннен кейін", "بعد الالتقاط", "Nach Aufnahme", "Dopo acquisizione", "Após capturar"),
      "settings.open_editor": row("Open Editor", "Abrir editor", "打开编辑器", "エディタを開く", "Ouvrir l’éditeur", "Открыть редактор", "Відкрити редактор", "Редакторды ашу", "فتح المحرر", "Editor öffnen", "Apri editor", "Abrir editor"),
      "settings.show_review": row("Show Capture Review", "Mostrar revisión", "显示截图回顾", "キャプチャ確認を表示", "Afficher la revue", "Показать быстрый обзор", "Показати огляд", "Шолуды көрсету", "عرض المراجعة", "Aufnahmeprüfung zeigen", "Mostra revisione", "Mostrar revisão"),
      "settings.theme_system": row("System", "Sistema", "系统", "システム", "Système", "Системная", "Системна", "Жүйе", "النظام", "System", "Sistema", "Sistema"),
      "settings.theme_light": row("Light", "Claro", "浅色", "ライト", "Clair", "Светлая", "Світла", "Ашық", "فاتح", "Hell", "Chiaro", "Claro"),
      "settings.theme_dark": row("Dark", "Oscuro", "深色", "ダーク", "Sombre", "Тёмная", "Темна", "Қараңғы", "داكن", "Dunkel", "Scuro", "Escuro"),
      "settings.capture_mode": row("Capture Mode", "Modo de captura", "截图模式", "キャプチャモード", "Mode de capture", "Режим снимка", "Режим знімка", "Түсіру режимі", "وضع الالتقاط", "Aufnahmemodus", "Modalità acquisizione", "Modo de captura"),
      "settings.capture_delay": row("Delay", "Retraso", "延迟", "遅延", "Délai", "Задержка", "Затримка", "Кідіріс", "تأخير", "Verzögerung", "Ritardo", "Atraso"),
      "settings.queue_panel": row("Keep session strip", "Mantener tira de sesión", "保留会话条", "セッションストリップを保持", "Garder la bande de session", "Показывать ленту сессии", "Показувати стрічку сесії", "Сессия жолағын сақтау", "إبقاء شريط الجلسة", "Sitzungsleiste behalten", "Mantieni barra sessione", "Manter faixa da sessão"),
      "settings.selection_shortcut": row("Selection Shortcut", "Atajo de selección", "区域截图快捷键", "範囲選択ショートカット", "Raccourci de sélection", "Сочетание для области", "Скорочення для області", "Аймақ пернесі", "اختصار تحديد المنطقة", "Kurzbefehl für Bereich", "Scorciatoia selezione", "Atalho de seleção"),
      "settings.fullscreen_shortcut": row("Full Screen Shortcut", "Atajo de pantalla completa", "全屏截图快捷键", "フルスクリーンショートカット", "Raccourci plein écran", "Сочетание для всего экрана", "Скорочення для всього екрана", "Толық экран пернесі", "اختصار ملء الشاشة", "Kurzbefehl für Vollbild", "Scorciatoia schermo intero", "Atalho de tela inteira"),
      "settings.record_shortcut": row("Record Shortcut", "Grabar atajo", "录制快捷键", "ショートカットを記録", "Enregistrer le raccourci", "Записать сочетание", "Записати скорочення", "Пернені жазу", "تسجيل الاختصار", "Kurzbefehl aufnehmen", "Registra scorciatoia", "Gravar atalho"),
      "settings.shortcut_recording": row("Press a letter or number with Command, Control, or Option", "Pulsa una letra o número con Comando, Control u Opción", "按下字母或数字，并同时按下 Command、Control 或 Option", "Command、Control、Option のいずれかと文字または数字を押してください", "Appuyez sur une lettre ou un chiffre avec Commande, Contrôle ou Option", "Нажмите букву или цифру вместе с Command, Control или Option", "Натисніть літеру або цифру з Command, Control чи Option", "Command, Control немесе Option пернесімен әріп не сан басыңыз", "اضغط حرفًا أو رقمًا مع Command أو Control أو Option", "Buchstabe oder Zahl mit Command, Control oder Option drücken", "Premi una lettera o un numero con Command, Control o Option", "Pressione uma letra ou número com Command, Control ou Option"),
      "settings.shortcut_invalid": row("Use a letter or number with Command, Control, or Option.", "Usa una letra o número con Comando, Control u Opción.", "请使用字母或数字，并搭配 Command、Control 或 Option。", "Command、Control、Option のいずれかと文字または数字を使用してください。", "Utilisez une lettre ou un chiffre avec Commande, Contrôle ou Option.", "Используйте букву или цифру с Command, Control или Option.", "Використовуйте літеру або цифру з Command, Control чи Option.", "Command, Control немесе Option пернесімен әріп не сан қолданыңыз.", "استخدم حرفًا أو رقمًا مع Command أو Control أو Option.", "Buchstabe oder Zahl mit Command, Control oder Option verwenden.", "Usa una lettera o un numero con Command, Control o Option.", "Use uma letra ou número com Command, Control ou Option."),
      "settings.shortcut_duplicate": row("This shortcut is already used.", "Este atajo ya está en uso.", "此快捷键已被使用。", "このショートカットはすでに使用されています。", "Ce raccourci est déjà utilisé.", "Это сочетание уже используется.", "Це скорочення вже використовується.", "Бұл перне тіркесімі қолданылып жатыр.", "هذا الاختصار مستخدم بالفعل.", "Dieser Kurzbefehl wird bereits verwendet.", "Questa scorciatoia è già in uso.", "Este atalho já está em uso."),
      "settings.export_preset": row("Export Preset", "Preajuste de exportación", "导出预设", "書き出しプリセット", "Préréglage d’export", "Пресет экспорта", "Пресет експорту", "Экспорт пресеті", "إعداد التصدير", "Exportvorgabe", "Predefinito esportazione", "Predefinição de exportação"),
      "settings.filename_template": row("Filename Template", "Plantilla de nombre", "文件名模板", "ファイル名テンプレート", "Modèle de nom de fichier", "Шаблон имени файла", "Шаблон імені файлу", "Файл атауы үлгісі", "قالب اسم الملف", "Dateinamenvorlage", "Modello nome file", "Modelo de nome"),
      "settings.watermark_text": row("Watermark Text", "Texto de marca", "水印文本", "透かしテキスト", "Texte du filigrane", "Текст водяного знака", "Текст водяного знака", "Су таңбасы мәтіні", "نص العلامة المائية", "Wasserzeichentext", "Testo filigrana", "Texto da marca"),
      "settings.watermark_logo": row("Watermark Logo", "Logo de marca", "水印标志", "透かしロゴ", "Logo du filigrane", "Логотип водяного знака", "Логотип водяного знака", "Су таңбасы логотипі", "شعار العلامة المائية", "Wasserzeichenlogo", "Logo filigrana", "Logo da marca"),
      "settings.watermark_preview_hint": row("Live rendered output", "Salida renderizada en vivo", "实时渲染输出", "ライブ出力", "Sortie rendue en direct", "Живой итоговый рендер", "Живий фінальний рендер", "Тікелей рендер", "إخراج مباشر", "Live gerenderte Ausgabe", "Output renderizzato live", "Saída renderizada ao vivo"),
      "settings.watermark_layout": row("Layout", "Distribución", "布局", "レイアウト", "Disposition", "Режим", "Режим", "Орналасу", "التخطيط", "Layout", "Layout", "Layout"),
      "settings.watermark_layout_single": row("Single", "Único", "单个", "単一", "Unique", "Один", "Один", "Бір", "مفرد", "Einzeln", "Singolo", "Único"),
      "settings.watermark_layout_tiled": row("Tiled", "Mosaico", "平铺", "タイル", "Mosaïque", "Плиткой", "Плиткою", "Тор", "متكرر", "Gekachelt", "Ripetuto", "Em mosaico"),
      "settings.watermark_position": row("Position", "Posición", "位置", "位置", "Position", "Позиция", "Позиція", "Орын", "الموضع", "Position", "Posizione", "Posição"),
      "settings.position.bottom_right": row("Bottom Right", "Abajo derecha", "右下", "右下", "Bas droite", "Снизу справа", "Унизу праворуч", "Төмен оң жақ", "أسفل اليمين", "Unten rechts", "In basso a destra", "Inferior direita"),
      "settings.position.bottom_left": row("Bottom Left", "Abajo izquierda", "左下", "左下", "Bas gauche", "Снизу слева", "Унизу ліворуч", "Төмен сол жақ", "أسفل اليسار", "Unten links", "In basso a sinistra", "Inferior esquerda"),
      "settings.position.top_right": row("Top Right", "Arriba derecha", "右上", "右上", "Haut droite", "Сверху справа", "Угорі праворуч", "Жоғары оң жақ", "أعلى اليمين", "Oben rechts", "In alto a destra", "Superior direita"),
      "settings.position.top_left": row("Top Left", "Arriba izquierda", "左上", "左上", "Haut gauche", "Сверху слева", "Угорі ліворуч", "Жоғары сол жақ", "أعلى اليسار", "Oben links", "In alto a sinistra", "Superior esquerda"),
      "settings.position.center": row("Center", "Centro", "居中", "中央", "Centre", "По центру", "По центру", "Ортасы", "الوسط", "Mitte", "Centro", "Centro"),
      "settings.watermark_spacing": row("Spacing", "Espaciado", "间距", "間隔", "Espacement", "Интервал", "Інтервал", "Аралық", "التباعد", "Abstand", "Spaziatura", "Espaçamento"),
      "settings.watermark_tile_pattern": row("Tile Pattern", "Patrón", "平铺模式", "タイルパターン", "Motif", "Узор плитки", "Візерунок плитки", "Тор үлгісі", "نمط التكرار", "Kachelmuster", "Motivo ripetuto", "Padrão"),
      "settings.tile.aligned": row("Aligned", "Alineado", "对齐", "整列", "Aligné", "Ровно", "Рівно", "Түзу", "محاذى", "Ausgerichtet", "Allineato", "Alinhado"),
      "settings.tile.brick": row("Brick", "Ladrillo", "砖块", "レンガ", "Brique", "Кирпичом", "Цеглинкою", "Кірпіш", "طوب", "Versetzt", "Mattone", "Tijolo"),
      "settings.tile.random": row("Random", "Aleatorio", "随机", "ランダム", "Aléatoire", "Случайно", "Випадково", "Кездейсоқ", "عشوائي", "Zufällig", "Casuale", "Aleatório"),
      "settings.watermark_tile_randomness": row("Randomness", "Aleatoriedad", "随机度", "ランダム度", "Aléatoire", "Случайность", "Випадковість", "Кездейсоқтық", "العشوائية", "Zufälligkeit", "Casualità", "Aleatoriedade"),
      "settings.logo_file": row("Logo File", "Archivo de logo", "标志文件", "ロゴファイル", "Fichier logo", "Файл логотипа", "Файл логотипа", "Логотип файлы", "ملف الشعار", "Logodatei", "File logo", "Arquivo do logo"),
      "settings.choose_logo": row("Choose…", "Elegir…", "选择…", "選択…", "Choisir…", "Выбрать…", "Вибрати…", "Таңдау…", "اختيار…", "Wählen…", "Scegli…", "Escolher…"),
      "settings.no_logo": row("No logo", "Sin logo", "无标志", "ロゴなし", "Aucun logo", "Нет логотипа", "Немає логотипа", "Логотип жоқ", "لا يوجد شعار", "Kein Logo", "Nessun logo", "Sem logo"),
      "settings.opacity": row("Opacity", "Opacidad", "不透明度", "不透明度", "Opacité", "Прозрачность", "Непрозорість", "Мөлдірлік", "الشفافية", "Deckkraft", "Opacità", "Opacidade"),
      "settings.size": row("Size", "Tamaño", "大小", "サイズ", "Taille", "Размер", "Розмір", "Өлшем", "الحجم", "Größe", "Dimensione", "Tamanho"),
      "settings.cleanup": row("Cleanup", "Limpieza", "清理", "クリーンアップ", "Nettoyage", "Очистка", "Очищення", "Тазалау", "تنظيف", "Bereinigung", "Pulizia", "Limpeza"),
      "settings.cleanup_never": row("Never", "Nunca", "从不", "しない", "Jamais", "Никогда", "Ніколи", "Ешқашан", "أبداً", "Nie", "Mai", "Nunca"),
      "settings.cleanup_duration": row("After duration", "Tras un periodo", "一段时间后", "一定時間後", "Après une durée", "Через время", "Через час", "Уақыттан кейін", "بعد مدة", "Nach Dauer", "Dopo durata", "Após período"),
      "settings.cleanup_age": row("Remove after", "Eliminar después de", "移除时间", "削除するまで", "Supprimer après", "Удалять через", "Видаляти через", "Кейін жою", "الإزالة بعد", "Entfernen nach", "Rimuovi dopo", "Remover após"),
      "settings.cleanup_saved": row("Include saved files", "Incluir guardados", "包括已保存文件", "保存済みファイルを含める", "Inclure les fichiers enregistrés", "Включая сохранённые файлы", "Включно зі збереженими", "Сақталған файлдарды қосу", "تضمين الملفات المحفوظة", "Gesicherte Dateien einschließen", "Includi file salvati", "Incluir arquivos salvos"),
      "settings.enable_ocr": row("Enable local OCR indexing", "Activar OCR local", "启用本地 OCR 索引", "ローカル OCR 索引を有効化", "Activer l’OCR local", "Включить локальный OCR", "Увімкнути локальний OCR", "Жергілікті OCR қосу", "تفعيل OCR المحلي", "Lokale OCR-Indexierung aktivieren", "Abilita OCR locale", "Ativar OCR local"),
      "settings.search_metadata": row("Enable searchable metadata", "Activar metadatos buscables", "启用可搜索元数据", "検索可能なメタデータを有効化", "Activer les métadonnées recherchables", "Включить поиск по метаданным", "Увімкнути пошук метаданих", "Метадерек іздеуді қосу", "تفعيل بيانات قابلة للبحث", "Durchsuchbare Metadaten aktivieren", "Abilita metadati cercabili", "Ativar metadados pesquisáveis"),
      "settings.choose_folder": row("Choose Folder…", "Elegir carpeta…", "选择文件夹…", "フォルダを選択…", "Choisir un dossier…", "Выбрать папку…", "Вибрати папку…", "Қалтаны таңдау…", "اختيار مجلد…", "Ordner wählen…", "Scegli cartella…", "Escolher pasta…"),
      "settings.save_location": row("Save Location", "Ubicación de guardado", "保存位置", "保存場所", "Emplacement d’enregistrement", "Папка сохранения", "Місце збереження", "Сақтау орны", "موقع الحفظ", "Speicherort", "Posizione salvataggio", "Local de salvamento"),
      "settings.default_pictures": row("Default (Pictures/QPARK Shot)", "Predeterminado (Imágenes/QPARK Shot)", "默认（图片/QPARK Shot）", "デフォルト（ピクチャ/QPARK Shot）", "Par défaut (Images/QPARK Shot)", "По умолчанию (Изображения/QPARK Shot)", "Типово (Зображення/QPARK Shot)", "Әдепкі (Суреттер/QPARK Shot)", "الافتراضي (الصور/QPARK Shot)", "Standard (Bilder/QPARK Shot)", "Predefinito (Immagini/QPARK Shot)", "Padrão (Imagens/QPARK Shot)"),
      "permission.title": row("Screen Recording Required", "Se requiere grabación de pantalla", "需要屏幕录制权限", "画面収録の許可が必要です", "Enregistrement d’écran requis", "Нужен доступ к записи экрана", "Потрібен доступ до запису екрана", "Экран жазу рұқсаты қажет", "يلزم إذن تسجيل الشاشة", "Bildschirmaufnahme erforderlich", "Serve registrazione schermo", "Gravação de tela necessária"),
      "permission.message": row("Allow QPARK Shot in System Settings, then retry capture.", "Permite QPARK Shot en Configuración del Sistema y vuelve a intentarlo.", "请在系统设置中允许 QPARK Shot，然后重试截图。", "システム設定で QPARK Shot を許可してから再試行してください。", "Autorisez QPARK Shot dans Réglages Système, puis réessayez.", "Разрешите QPARK Shot в системных настройках и повторите.", "Дозвольте QPARK Shot у системних налаштуваннях і повторіть.", "Жүйе параметрлерінде QPARK Shot рұқсатын беріп, қайталаңыз.", "اسمح لـ QPARK Shot من إعدادات النظام ثم أعد المحاولة.", "Erlaube QPARK Shot in den Systemeinstellungen und versuche es erneut.", "Consenti QPARK Shot in Impostazioni di Sistema e riprova.", "Permita QPARK Shot nos Ajustes do Sistema e tente novamente."),
      "permission.open_settings": row("Open System Settings", "Abrir Configuración del Sistema", "打开系统设置", "システム設定を開く", "Ouvrir Réglages Système", "Открыть системные настройки", "Відкрити системні налаштування", "Жүйе параметрлерін ашу", "فتح إعدادات النظام", "Systemeinstellungen öffnen", "Apri Impostazioni di Sistema", "Abrir Ajustes do Sistema"),
      "status.capture_cancelled": row("Capture canceled.", "Captura cancelada.", "截图已取消。", "キャプチャをキャンセルしました。", "Capture annulée.", "Снимок отменён.", "Знімок скасовано.", "Түсіру тоқтатылды.", "تم إلغاء الالتقاط.", "Aufnahme abgebrochen.", "Acquisizione annullata.", "Captura cancelada."),
      "status.capture_failed": row("Capture failed.", "No se pudo capturar.", "截图失败。", "キャプチャに失敗しました。", "Échec de la capture.", "Не удалось сделать снимок.", "Не вдалося зробити знімок.", "Түсіру сәтсіз.", "فشل الالتقاط.", "Aufnahme fehlgeschlagen.", "Acquisizione non riuscita.", "Falha ao capturar."),
      "status.capturing": row("Capturing…", "Capturando…", "正在截图…", "キャプチャ中…", "Capture…", "Снимаем…", "Знімаємо…", "Түсірілуде…", "جارٍ الالتقاط…", "Aufnahme…", "Acquisizione…", "Capturando…"),
      "status.indexing": row("Indexing text…", "Indexando texto…", "正在索引文本…", "テキストを索引中…", "Indexation du texte…", "Индексация текста…", "Індексація тексту…", "Мәтін индекстелуде…", "جارٍ فهرسة النص…", "Text wird indexiert…", "Indicizzazione testo…", "Indexando texto…"),
      "status.ocr_disabled": row("OCR is off", "OCR desactivado", "OCR 已关闭", "OCR はオフです", "OCR désactivé", "OCR выключен", "OCR вимкнено", "OCR өшірулі", "OCR متوقف", "OCR ist aus", "OCR disattivato", "OCR desligado"),
      "status.ready": row("Ready", "Listo", "就绪", "準備完了", "Prêt", "Готово", "Готово", "Дайын", "جاهز", "Bereit", "Pronto", "Pronto"),
      "status.no_text": row("No text found", "No se encontró texto", "未找到文本", "テキストが見つかりません", "Aucun texte trouvé", "Текст не найден", "Текст не знайдено", "Мәтін табылмады", "لم يتم العثور على نص", "Kein Text gefunden", "Nessun testo trovato", "Nenhum texto encontrado"),
      "status.loading": row("Loading…", "Cargando…", "正在加载…", "読み込み中…", "Chargement…", "Загрузка…", "Завантаження…", "Жүктелуде…", "جارٍ التحميل…", "Laden…", "Caricamento…", "Carregando…"),
      "status.copy_failed": row("Copy failed.", "No se pudo copiar.", "复制失败。", "コピーに失敗しました。", "Échec de la copie.", "Не удалось скопировать.", "Не вдалося скопіювати.", "Көшіру сәтсіз.", "فشل النسخ.", "Kopieren fehlgeschlagen.", "Copia non riuscita.", "Falha ao copiar."),
      "status.delete_failed": row("Delete failed.", "No se pudo eliminar.", "删除失败。", "削除に失敗しました。", "Échec de la suppression.", "Не удалось удалить.", "Не вдалося видалити.", "Жою сәтсіз.", "فشل الحذف.", "Löschen fehlgeschlagen.", "Eliminazione non riuscita.", "Falha ao excluir."),
      "status.moved_to_trash": row("Moved to Trash.", "Movido a la papelera.", "已移到废纸篓。", "ゴミ箱に移動しました。", "Placé dans la corbeille.", "Перемещено в Корзину.", "Переміщено в Смітник.", "Себетке жылжытылды.", "تم النقل إلى سلة المهملات.", "In den Papierkorb bewegt.", "Spostato nel Cestino.", "Movido para o Lixo."),
      "status.missing_forgotten": row("Missing item forgotten.", "Elemento ausente olvidado.", "已忽略丢失项目。", "見つからない項目の登録を解除しました。", "Élément manquant oublié.", "Запись о потерянном файле удалена.", "Запис про відсутній файл видалено.", "Жоғалған файл жазбасы өшірілді.", "تم نسيان العنصر المفقود.", "Fehlendes Element vergessen.", "Elemento mancante dimenticato.", "Item ausente esquecido."),
      "status.unsupported_image": row("Choose a supported image file.", "Elige un archivo de imagen compatible.", "请选择受支持的图像文件。", "対応している画像ファイルを選択してください。", "Choisissez un fichier image pris en charge.", "Выберите поддерживаемый файл изображения.", "Виберіть підтримуваний файл зображення.", "Қолдау көрсетілетін сурет файлын таңдаңыз.", "اختر ملف صورة مدعومًا.", "Unterstützte Bilddatei wählen.", "Scegli un file immagine supportato.", "Escolha um arquivo de imagem compatível."),
      "status.relink_failed": row("Could not relink the file.", "No se pudo volver a vincular el archivo.", "无法重新关联文件。", "ファイルを再リンクできませんでした。", "Impossible de relier le fichier.", "Не удалось перепривязать файл.", "Не вдалося переприв’язати файл.", "Файлды қайта байланыстыру мүмкін болмады.", "تعذر إعادة ربط الملف.", "Datei konnte nicht neu verknüpft werden.", "Impossibile ricollegare il file.", "Não foi possível vincular o arquivo novamente."),
      "status.relinked": row("File relinked.", "Archivo vinculado de nuevo.", "文件已重新关联。", "ファイルを再リンクしました。", "Fichier relié.", "Файл перепривязан.", "Файл переприв’язано.", "Файл қайта байланыстырылды.", "تمت إعادة ربط الملف.", "Datei neu verknüpft.", "File ricollegato.", "Arquivo vinculado novamente."),
      "status.cleanup_completed": row("Cleanup completed.", "Limpieza completada.", "清理完成。", "クリーンアップが完了しました。", "Nettoyage terminé.", "Очистка завершена.", "Очищення завершено.", "Тазалау аяқталды.", "اكتمل التنظيف.", "Bereinigung abgeschlossen.", "Pulizia completata.", "Limpeza concluída."),
      "status.cleanup_failed": row("Some files could not be cleaned up.", "No se pudieron limpiar algunos archivos.", "部分文件无法清理。", "一部のファイルを削除できませんでした。", "Certains fichiers n’ont pas pu être nettoyés.", "Некоторые файлы не удалось очистить.", "Деякі файли не вдалося очистити.", "Кейбір файлдар тазаланбады.", "تعذر تنظيف بعض الملفات.", "Einige Dateien konnten nicht bereinigt werden.", "Impossibile pulire alcuni file.", "Alguns arquivos não puderam ser limpos."),
      "status.visible": row("Visible", "Visible", "可见", "表示", "Visible", "Показано", "Показано", "Көрсетіледі", "ظاهر", "Sichtbar", "Visibile", "Visível"),
      "status.hidden": row("Hidden", "Oculto", "已隐藏", "非表示", "Masqué", "Скрыто", "Приховано", "Жасырын", "مخفي", "Ausgeblendet", "Nascosto", "Oculto"),
      "status.selected": row("Selected", "Seleccionado", "已选择", "選択済み", "Sélectionné", "Выбрано", "Вибрано", "Таңдалды", "محدد", "Ausgewählt", "Selezionato", "Selecionado"),
      "export.preset.clean": row("Clean PNG", "PNG limpio", "干净 PNG", "クリーン PNG", "PNG propre", "Чистый PNG", "Чистий PNG", "Таза PNG", "PNG نظيف", "Sauberes PNG", "PNG pulito", "PNG limpo"),
      "export.preset.watermarked": row("Watermarked", "Con marca", "带水印", "透かし付き", "Avec filigrane", "С водяным знаком", "З водяним знаком", "Су таңбасымен", "بعلامة مائية", "Mit Wasserzeichen", "Con filigrana", "Com marca"),
      "export.preset.support": row("For Support", "Para soporte", "用于支持", "サポート用", "Pour le support", "Для поддержки", "Для підтримки", "Қолдау үшін", "للدعم", "Für Support", "Per supporto", "Para suporte")
    ]
  }()
}

struct LText: View {
  @ObservedObject private var localization = LocalizationController.shared
  let key: String

  var body: some View {
    Text(localization.text(key))
  }
}

extension View {
  func qparkLocalizationEnvironment() -> some View {
    let localization = LocalizationController.shared
    return environment(\.locale, localization.locale)
      .environment(\.layoutDirection, localization.layoutDirection)
  }
}
