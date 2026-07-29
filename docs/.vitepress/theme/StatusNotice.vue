<script setup lang="ts">
import { useData } from 'vitepress'
import { computed } from 'vue'
import { statusByPath } from '../processes'

const { page, frontmatter } = useData()

// Статус текущей страницы-процесса (кружок из processes.ts):
//   🔴 — раздел на этапе согласования; ⚪ — раздел в работе у разработчиков.
const status = computed(() => statusByPath[page.value.relativePath])

// Показываем только на процессных страницах (у них есть статус) и если не отключено frontmatter.
const show = computed(() => {
  if (frontmatter.value.statusNotice === false) return false
  return !!status.value
})
</script>

<template>
  <div
    v-if="show"
    class="status-notice"
    :class="status === '🔴' ? 'status-notice--review' : 'status-notice--wip'"
    role="note"
  >
    <span class="status-notice__dot" aria-hidden="true">{{ status }}</span>
    <span v-if="status === '🔴'">
      <strong>Раздел на этапе согласования.</strong>
      После утверждения всей бизнес-логики в течение 48&nbsp;часов будет выполнено
      полное тестирование разработчиками, после чего раздел перейдёт к публичному
      тестированию пользователями.
    </span>
    <span v-else>
      <strong>Раздел в работе у разработчиков.</strong>
      Мы дорабатываем и перепроверяем содержимое. Как только раздел будет готов,
      он перейдёт к согласованию бизнес-логики с заказчиком.
    </span>
  </div>
</template>

<style scoped>
.status-notice {
  display: flex;
  gap: 10px;
  align-items: flex-start;
  border: 1px solid var(--vp-c-default-2);
  background: var(--vp-c-default-soft);
  border-radius: 8px;
  padding: 12px 16px;
  margin: 0 0 24px;
  font-size: 14px;
  line-height: 1.55;
}
/* Раздел в работе — нейтрально-серый. */
.status-notice--wip {
  border-color: var(--vp-c-default-2);
  background: var(--vp-c-default-soft);
}
/* Раздел на согласовании — акцентный (янтарный). */
.status-notice--review {
  border-color: var(--vp-c-warning-1);
  background: var(--vp-c-warning-soft);
}
.status-notice__dot {
  flex: none;
  line-height: 1.55;
}
</style>
