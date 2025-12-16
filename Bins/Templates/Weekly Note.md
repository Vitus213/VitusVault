---
created: <% tp.file.creation_date() %>
fellings:
tags:
  - review/monthly
---


# <% tp.file.title %> 周复盘

## 📅 本周导航
[[<% tp.date.now("gggg-[W]ww", -7, tp.file.title, "gggg-[W]ww") %>|⬅️ 上一周]] | [[<% tp.date.now("gggg-[W]ww", 7, tp.file.title, "gggg-[W]ww") %>|➡️ 下一周]] | [[<% tp.date.now("YYYY-MM", 0, tp.file.title, "gggg-[W]ww") %>|📅 本月]]

## 🎯 本周目标
- [ ] 

## 📝 每日记录
<%* // 这段脚本会自动列出本周7天的日记链接
const currentWeek = tp.date.now("gggg-[W]ww", 0, tp.file.title, "gggg-[W]ww");
const days = [1, 2, 3, 4, 5, 6, 7];
days.forEach(day => {
  const dateStr = moment(currentWeek, "gggg-[W]ww").day(day).format("YYYY-MM-DD");
  tR += `- [[${dateStr}]] \n`;
}) 
%>

#### 🟢 本周创建 (Created This Week)
> [!example]- Created This Week
> ```dataview
> table without id
> file.link as Note,
> file.folder as Folder,
> file.ctime as "Created"
> FROM ""
> WHERE file.ctime >= date(<% moment(tp.file.title, 'gggg-[W]ww').startOf('isoWeek').format("YYYY-MM-DD") %>) 
> AND file.ctime < date(<% moment(tp.file.title, 'gggg-[W]ww').add(1, 'weeks').startOf('isoWeek').format("YYYY-MM-DD") %>)
> AND file.path != this.file.path
> sort file.ctime desc
> ```


#### 🟡 本周修改 (Modified This Week)
> [!example]- Modified This Week
> ```dataview
> table without id
> file.link as Note,
> file.folder as Folder,
> file.mtime as "Last Modified"
> FROM ""
> WHERE file.mtime >= date(<% moment(tp.file.title, 'gggg-[W]ww').startOf('isoWeek').format("YYYY-MM-DD") %>) 
> AND file.mtime < date(<% moment(tp.file.title, 'gggg-[W]ww').add(1, 'weeks').startOf('isoWeek').format("YYYY-MM-DD") %>)
> AND file.path != this.file.path
> sort file.mtime desc
> ```


## 💡 本周总结