-- 此文件仅用于定义变量和子函数。
-- 下降高度
local get_height = 73.7
-- 目标点上空高度
local trans_height = 100.02
-- x方向末端补偿
local dx = {61.1367, -61.1367}
-- y方向末端补偿
local dy = {-2.3016, 2.3016}
-- rz方向末端补偿
local rz = {-0, -180}
-- 末端补偿状态
local rz_status = 1
-- 水平运动加速度
local a_horizontal = {
    a = 100
}
-- 垂直下降运动加速度
local a_vertical = {
    a = 2
}

--- 字节流转浮点数
-- 将四个字节转换为浮点数
---@param b1 number 字节1
---@param b2 number 字节2
---@param b3 number 字节3
---@param b4 number 字节4
---@return table 一个浮点数
function bytes2float(b1, b2, b3, b4)
    local packedBytes = string.pack("BBBB", b1, b2, b3, b4)
    local floatValue = string.unpack("f", packedBytes)
    return floatValue
end

--- 执行数据转换
-- 将12字节的字节流转换为浮点数
---@param stream table 12字节的字节流
---@return table 三个浮点数
function exec(stream)
    local x = bytes2float(stream[1], stream[2], stream[3], stream[4])
    local y = bytes2float(stream[5], stream[6], stream[7], stream[8])
    local c = bytes2float(stream[9], stream[10], stream[11], stream[12])
    return {x, y, c}
end

--- 接收数据
-- 从上位机接收数据
---@param socket any socket
---@return table 位置和颜色，res[1]为x坐标，res[2]为y坐标，res[3]为颜色
function rec(socket)
    -- 接收数据
    local err, recBuf = TCPRead(socket, 30, "table")
    -- 执行数据转换
    local res = exec(recBuf)
    return res
end

-- 吸取棋子
function get()
    DO(9, ON)
    DO(11, OFF)
    Wait(70)
end

-- 释放棋子
function push()
    DO(9, OFF)
    DO(11, ON)
    Wait(50)
end

--- 打印位置和状态
-- 格式化打印x、y坐标和rz状态
---@param M2 table 位置
---@return nil 无返回值
function printPoseAndStatus(M2)
    local s = string.format("x = %.4f,y = %.4f, rz_statue = %d", M2.pose[1], M2.pose[2], rz_status)
    print(s)
end

--- 执行直线运动或关节运动
-- 如果可以直线运动，则直线运动，否则关节运动
---@param M2 table 目标位置
---@param a3 table 加速度（取值范围0~100）
---@return number 0为可以运动，1为不能运动
function performMovement(M2, a3, offset)
    printPoseAndStatus({
        pose = M2
    })
    -- print(CheckMovJ({pose=M2}))
    -- print(CheckMovL({pose=M2}))
    -- 如果可以直线运动，则直线
    if CheckMovL({
        pose = M2
    }) == 0 then
        -- 获取第六个关节的角度
        local joint = GetAngle().joint[6]
        print("joint:", joint)
        -- 如果需要j6关节偏移
        if offset then
            -- 先检测当前位置，防止碰撞摄像头杆
            local x_now = GetPose().pose[1]
            local y_now = GetPose().pose[2]
            -- 危险位置，需要撤步以避开
            if x_now < 310 and y_now < -100 then
                print("危险位置")
                RelMovJUser({20, 20, 5, 0, 0, 0})
            end
            -- 关节j6超出安全区域
            if joint > 200 then
                -- 执行偏移关节运动
                RelJointMovJ({0, 0, 0, 0, 0, -joint}, a3)
            elseif joint > 100 or joint < -100 then
                -- 执行偏移关节运动
                RelJointMovJ({0, 0, 0, 0, 0, -joint}, a3)
            end
        end
        MovL({
            pose = M2
        }, a3)
        return 0
        -- 如果不能直线运动，则关节运动
    elseif CheckMovJ({
        pose = M2
    }) == 0 then
        MovJ({
            pose = M2
        }, a3)
        return 0
    end
    return 1
end

--- 运动参数计算
-- 计算移动棋子所需的运动参数，执行相应的校正和补偿
---@param M2 table 位置
---@param a2 table 加速度
---@return number 0为成功，1为失败
function calculateParams(M2, a2)
    local M3 = {table.unpack(M2)}
    -- 地理围栏
    -- 如果x<300, y<30，说明靠近机械臂，需要rz为0
    if M3[1] < 300 and M3[2] < 3 then
        rz_status = 1
        -- 如果x>365, y<30，说明远离机械臂，靠近外缘，需要rz为180
    elseif M3[1] > 365 and M3[2] < 3 then
        rz_status = 2
    end
    -- 末端补偿
    M3[1] = M3[1] + dx[rz_status]
    M3[2] = M3[2] + dy[rz_status]
    M3[6] = rz[rz_status]
    print(rz_status)
    -- 尝试移动，如果失败则切换rz状态，末端旋转
    if performMovement(M3, a2, false) == 1 then
        M3[1] = M3[1] + dx[3 - rz_status] * 2
        M3[2] = M3[2] + dy[3 - rz_status] * 2
        M3[6] = rz[3 - rz_status]
        if performMovement(M3, a2, true) == 1 then
            return 1
        else
            rz_status = 3 - rz_status
            return 0
        end
    else
        return 0
    end
end

--- 运动总函数
-- 棋子运动的核心函数
---@param res table 位置和颜色，res[1]为x坐标，res[2]为y坐标，res[3]为颜色
---@return string 0为成功，1为失败
function move(res)
    -- M1为目标棋子位置，M2为目标点高点
    local M1 = {res[1], res[2], get_height, -180, 0, -90}
    local M2 = {res[1], res[2], trans_height, -180, 0, -90}
    -- K1为黑棋筐的位置，K2为白棋筐的位置
    K1 = {P1.pose[1], P1.pose[2], trans_height, -180, 0, -90}
    K2 = {P2.pose[1], P2.pose[2], trans_height, -180, 0, -90}
    -- 如果是黑棋，对棋盘中心区域做高度补偿，降低0.3mm
    if res[3] == 0 and M1[1] < 370 and M1[1] > 300 then
        M1[3] = M1[3] - 0
        -- 应当再对靠近棋筐片区加大补偿
    end
    -- 去目标点上空
    if calculateParams(M2, a_horizontal) == 1 then
        return "1"
    end
    -- 下降
    if calculateParams(M1, a_vertical) == 1 then
        return "1"
    end
    -- 吸取棋子
    get()
    -- 抬升至上空
    if calculateParams(M2, {
        a = 6
    }) == 1 then
        return "1"
    end
    -- 如果是黑色，前往黑棋筐
    if res[3] == 0 then
        if calculateParams(K1, a_horizontal) == 1 then
            return "1"
        end
        -- 如果是白色，前往白棋筐
    elseif res[3] == 1 then
        if calculateParams(K2, a_horizontal) == 1 then
            return "1"
        end
    end
    -- 释放棋子
    push()
    DO(11, OFF)
    return "0"
end

--- 点位同步
---@param socket any socket
---@return nil 无返回值
function sync(socket)
    -- 读取点位
    -- P1是黑棋筐，P2是白棋筐，P3~P11是九点
    local p = {P1, P2, P3, P4, P5, P6, P7, P8, P9, P10, P11}
    local res = {}
    for index, value in ipairs(p) do
        table.insert(res, value.pose[1])
        table.insert(res, value.pose[2])
        -- TCPWrite(socket, tostring(value.pose[1]))
        -- TCPWrite(socket, tostring(value.pose[2]))
    end
    local sentence = table.concat(res, ",")
    -- 发送至上位机
    TCPWrite(socket, sentence)
    return
end

function check(res)
    local M1 = {res[1], res[2], get_height, -180, 0, -90}
    if CheckMovL({
        pose = M1
    }) == 0 then
        return 0
    else
        return 255
    end

end

function test_main(socket)
    local err, stream = TCPRead(socket, 10, "table")
    print(stream)
    local x = bytes2float(stream[1], stream[2], stream[3], stream[4])
    local y = bytes2float(stream[5], stream[6], stream[7], stream[8])
    local res = check({x, y})
    TCPWrite(socket, tostring(res))
end

function test(res)
    local M1 = {res[1], res[2], get_height, -180, 0, -90}
    local M2 = {res[1], res[2], trans_height, -180, 0, -90}
    print(M1)
    print(CheckMovL({
        pose = M2
    }))
    K1 = {P1.pose[1], P1.pose[2], trans_height, -180, 0, -90}
    K2 = {P2.pose[1], P2.pose[2], trans_height, -180, 0, -90}
    if res[3] == 0 then
        MovL({
            pose = K1
        })
    elseif res[3] == 1 then
        MovL({
            pose = K2
        })
    end
    DO(11, OFF)
    return
end
