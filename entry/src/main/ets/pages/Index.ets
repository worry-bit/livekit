import liveKitUtil from '../rtc/LiveKitUtil';

@Entry
@Component
struct Index {
  build() {
    Column() {
      Row() {
        Button('获取麦克风权限')
          .onClick(() => {
            liveKitUtil.requestPermissions()
          })
        Button('加入房间')
          .onClick(() => {
            const  token ='your-token'
            const  url = 'your-wss'
            liveKitUtil.joinRoom(url,token)
          })
        Button('退出房间')
          .onClick(() => {
            liveKitUtil.leaveRoom()
          })
      }
    }
    .height('100%')
    .width('100%')
  }
}