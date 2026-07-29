<script setup lang="ts">
import { useData } from 'vitepress'
import { watch, onMounted, onUnmounted } from 'vue'
import { processNumberByPath } from '../processes'

// Компонент ничего не рисует. Его задача — на страницах-процессах выставить на
// <html> номер страницы (CSS-переменная --proc-no) и флаг data-proc-active,
// чтобы CSS-счётчики (custom.css) авто-нумеровали разделы как «N.1, N.2…».
// На остальных страницах атрибуты снимаются — нумерации нет.
const { page } = useData()

function apply() {
  if (typeof document === 'undefined') return
  const root = document.documentElement
  const n = processNumberByPath[page.value.relativePath]
  if (n) {
    // Значение уже в кавычках: в CSS `content` переменная подставляется как
    // токен, а «голое» число там невалидно — нужна строка ("7").
    root.style.setProperty('--proc-no', `"${n}"`)
    root.setAttribute('data-proc-active', '')
  } else {
    root.style.removeProperty('--proc-no')
    root.removeAttribute('data-proc-active')
  }
}

onMounted(() => {
  apply()
  watch(() => page.value.relativePath, apply)
})

onUnmounted(() => {
  if (typeof document === 'undefined') return
  document.documentElement.style.removeProperty('--proc-no')
  document.documentElement.removeAttribute('data-proc-active')
})
</script>

<template><span style="display: none" /></template>
