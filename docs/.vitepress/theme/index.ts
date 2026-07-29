import DefaultTheme from 'vitepress/theme'
import { h } from 'vue'
import StatusNotice from './StatusNotice.vue'
import ProcessSectionNumber from './ProcessSectionNumber.vue'
import './custom.css'

// Расширяем стандартную тему:
//  - layout-top: невидимый компонент, включающий авто-нумерацию разделов
//    на страницах-процессах (см. ProcessSectionNumber.vue + custom.css);
//  - doc-before: ноутис о статусе согласования (см. StatusNotice.vue).
export default {
  extends: DefaultTheme,
  Layout() {
    return h(DefaultTheme.Layout, null, {
      'layout-top': () => h(ProcessSectionNumber),
      'doc-before': () => h(StatusNotice),
    })
  },
}
