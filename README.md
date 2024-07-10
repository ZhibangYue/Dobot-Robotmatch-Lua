# Dobot-Robotmatch-Lua
2024中国工程机器人大赛暨国际公开赛山东大学13队（项目：桌面机械臂11棋子分拣）

机械臂运动控制程序，使用Lua语言开发

## 工程结构

程序由两个文件构成：

- `src0.lua`为主程序，直接执行
- `global.lua`用于定义变量和子函数，对主程序可见

## 注意事项
每次**环境变更**必须更新的常量包括：

1. 下降高度`get_height`
2. 地理围栏（在函数`calculateParams`中）
3. 黑棋下降高度补偿（在函数`move`中）

可能需要更新的常量包括：

1. 关节J6安全区（在函数`performMovement`中）
2. 垂直下降运动加速度（`a_vertical`）

## 修订说明

### V1.0

基本实现所有功能，现场总线同步性丢失的问题仍未解决。