while true do
    err, socket = TCPCreate(false, "192.168.5.2", 8081)
    -- 建立连接，如果成功则返回0
    local err = TCPStart(socket, 5)
    -- 当环境变更时需要重新与上位机同步数据
    -- sync(socket)

    if err == 0 then
        status = "0"
        while true do
            TCPWrite(socket, status)
            local res = rec(socket)
            if res == 0 then
               goto continue
            end
            -- print(res)
            status = move(res)
            -- test_main(socket)
            -- test(res)
            ::continue::
        end
        TCPDestroy(socket)
    end
end
