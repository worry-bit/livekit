export class  RtcModel{
  participant:IdentityModel = new IdentityModel()


}
export class IdentityModel{
  identity:string = ''
}

export class TokenBean{
  token:string = ''
}

export class SpeakerModel{
  speakers:Array<Speaker> = new Array<Speaker>()
}
export class Speaker{
  sid:string =''
}