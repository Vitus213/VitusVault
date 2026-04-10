## JWT
### 当前实现

Json Web Token 无服务状态密钥，在客户端和服务端之间传递身份证明 

-  无状态
- 服务端不用强依赖session存储
- 适合API/前后端分离

三段式： Header.Payload.Signature

- Payload：也叫claims，是token里真正携带的数据，存sub(subject，整个token

  属于谁即UUID，exp（超时时间），iat（签发时间）

  还有别的常见字段：

  1. iss （issuer签发者）
  2. aud（audience接收方）
  3. nbf( not before 生效时间)
  4. jti(jwt id ，token的唯一编号，可以撤销token，防重放，做黑名单，)

- Signature： 签名，依赖： Header+Payload 和jwt_secret

jwt按照Beader Token 的方式放到HTTP头里面 

HS256（sha-256算法需要jwt_secret) + 独立 secret + exp 校验 + Bearer header + 中间件统一校验

### 改进方向

如何去管理多端会话 

1. 扩写jwt字段，

   1. jti（token 的唯一编号）
   2. sid（会话id）
   3. iss
   4. aud

2. 数据库增添会话表 

   新增加一张user-session表

   1. session_id

   2. user_id

   3. device_type,device_name

   4. refresh_token_hash(续签token)

      ...

3. 想要实现设备级登出

   1. 短期 access token
   2. 长期refresh token 和session（sid) 绑定

4. 想要实现立即登出

   1. 每次请求都查session状态（每次都要查数据库/Redis）
   2. 短access token + 可撤销refresh token 不能保证旧的access token 立即失效 
   3. 构建jti的黑名单，每次请求都验证jti




## 密码存储

### 加盐哈希

用户注册时：

 用 Argon2 PHC 字符串存盐+哈希，不单独建 salt 列，

- 每次注册时，使用操作系统提供的安全随机源生成一个随机盐
- 把算法参数（内存/迭代次数/并行度）+盐+哈希值一起算出一个密码哈希对象转成字符串-》phc string 
- 所以直接把这个phc string作为一个password哈希值存在数据库中，不需要单独存一个salt列了 

用户登录时

- 每次验证是把这个hash值取出来，然后取出hash值中的 salt和参数
- 把明文密码按照salt和参数再算一遍
- 比较结果是否一致

