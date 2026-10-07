---
id: {{ID}}
title: '{{TITLE}}'
type: {{TYPE}}
status: draft
priority: P2
created: {{DATE}}
updated: {{DATE}}
# --- опциональные поля: раскомментировать при необходимости ---
# assignee:
# tags: []
# blocked-by: []          # id блокирующих задач; внешний блокер — без этого поля, комментарий NNN-blocked-<slug>.md
# relates-to: []          # связанные задачи (дубликаты, предыстория)
# branch:                 # ветка исполнения: ai/qt-<slug> (quick-задачи) / ai/<NNN>-<desc> (план-задачи)
# lock:                   # .task-locks/qt-<name>.lock.json (quick) либо .task-locks/<NNN>.lock.json (план)
# spec:                   # путь к спеке/плану в Docs/packages/
# env:                    # только bug: {os: iOS 26.1, build: "1.4.2 (318)", device: iPhone 16 Pro}
# closed: {{DATE}}        # заполняется при done/cancelled
# resolution: fixed       # done: fixed (баги) | done (остальное); cancelled: wont-fix | duplicate | obsolete
---

<!--
  Неприменимые разделы удалить; соответствие «раздел × тип» — в
  IskInFlow/guides/task_tracker.md (раздел Types).
  Вложения отдельным разделом не создавать: файлы в attachments/ упоминать
  по месту в тексте относительными ссылками (attachments/crash.png).
-->

## Описание

<!-- Что происходит / чего не хватает / что исследуем и зачем. -->

## Шаги воспроизведения

<!-- Только bug. -->

1.
2.

**Фактическое поведение:**

**Ожидаемое поведение:**

## Критерии готовности

<!-- feature / improvement / task — обязательно; для bug — опционально. -->

- [ ]

## Открытые вопросы

<!-- Только product-research / tech-research — обязательно. -->

-

## Результат

<!-- product-research / tech-research — обязательно: итог проработки и решение.
     Результат проработки также фиксируется спекой (поле spec выше). -->
