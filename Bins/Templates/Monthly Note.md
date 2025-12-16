---
tags: [review/monthly]
created: <% tp.file.creation_date() %>
---

# 📅 <% tp.file.title %> 月度复盘

## 🧭 时间导航
[[30-Monthly/<% moment(tp.file.title, "YYYY-MM").subtract(1, 'M').format("YYYY-MM") %>|⬅️ 上个月]] | [[30-Monthly/<% moment(tp.file.title, "YYYY-MM").add(1, 'M').format("YYYY-MM") %>|➡️ 下个月]] | [[00-Yearly/<% tp.file.title.split("-")[0] %>|🔺 年度目标]]

---

## 🔗 本月周记回顾
> 自动汇总本月包含的周记，点击回顾每周重点：

<%*
// 自动化脚本：计算本月包含哪几周，并生成带路径的链接
const currentMonth = moment(tp.file.title, "YYYY-MM");
const year = currentMonth.year();
const month = currentMonth.month(); // 0-11
const weeks = [];

// 遍历这个月的每一天，找到涉及的周号
let startWeek = currentMonth.clone().startOf('month').week();
let endWeek = currentMonth.clone().endOf('month').week();

// 处理跨年周的特殊情况 (例如12月最后一周可能是第1周，或者1月第一周是去年的52周)
if (startWeek > endWeek && endWeek < 5) {
    // 这种情况通常发生在12月跨到1月，简单处理：列出 startWeek 到年底，和 1 到 endWeek
    // 这里为了简化，我们通常列出这月每一天所属的周，去重
}

let uniqueWeeks = new Set();
let dateIterator = currentMonth.clone().startOf('month');
const endDate = currentMonth.clone().endOf('month');

while (dateIterator.isBefore(endDate) || dateIterator.isSame(endDate)) {
    // 获取 ISO 周号格式 (如 2025-W01)
    let weekStr = dateIterator.format("gggg-[W]ww");
    uniqueWeeks.add(weekStr);
    dateIterator.add(1, 'day');
}

// 输出周记链接
Array.from(uniqueWeeks).sort().forEach(week => {
    // ⚠️ 请修改下面的 "20-Weekly" 为你真实的周记文件夹路径
    tR += `- [[20-Weekly/${week}|${week} 周记]] \n`;
})
%>

---
#### 🟢 本月创建 (Created This Month)

> [!example]- Created This Month
> ```dataview
> table without id
> file.link as Note,
> file.folder as Folder,
> file.ctime as "Created"
> FROM ""
> WHERE file.ctime >= date(<% moment(tp.file.title, 'YYYY-MM').startOf('month').format("YYYY-MM-DD") %>) 
> AND file.ctime < date(<% moment(tp.file.title, 'YYYY-MM').add(1, 'months').startOf('month').format("YYYY-MM-DD") %>)
> AND file.path != this.file.path
> sort file.ctime desc

#### 🟡 本月修改 (Modified This Month)

> [!example]- Modified This Month
> ```dataview
> table without id
> file.link as Note,
> file.folder as Folder,
> file.mtime as "Last Modified"
> FROM ""
> WHERE file.mtime >= date(<% moment(tp.file.title, 'YYYY-MM').startOf('month').format("YYYY-MM-DD") %>) 
> AND file.mtime < date(<% moment(tp.file.title, 'YYYY-MM').add(1, 'months').startOf('month').format("YYYY-MM-DD") %>)
> AND file.path != this.file.path
> sort file.mtime desc


## 🏆 本月高光时刻 (Big Wins)
*在此记录本月最有成就感的 3 件事*
1. 
2. 
3. 

## 📉 反思与改进 (Review)
| 维度 | 做的好的 (Keep) | 需要改进的 (Improve) | 尝试新方法 (Try) |
| :--- | :--- | :--- | :--- |
| **工作/学习** |  |  |  |
| **生活/健康** |  |  |  |
| **财务/其他** |  |  |  |

## 📊 关键指标追踪
*(根据需要填写)*
- 📚 阅读书籍：
- 🏃 运动次数：
- 💰 结余储蓄：

---

## 🔭 下月展望
### 核心目标 (Top 3)
> 基于本月的复盘，下个月最重要的目标是什么？
1. 
2. 
3. 

### 待办事项迁移
```dataview
task
WHERE !completed AND file.name = this.file.name