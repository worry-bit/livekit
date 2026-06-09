import { describe, beforeAll, beforeEach, afterEach, afterAll, it, expect } from '@ohos/hypium';
import { parseKooInstanceAuthResponse } from '../main/ets/koophone/KooAuthParser';
import { KooInstancePoolEntry, selectNextAvailableKooInstance } from '../main/ets/koophone/KooInstancePool';
import {
  buildKooLiveSurfaceComponentId,
  canStartKooLiveAddSelection,
  getKooLiveAddOptionTitle,
  isKooLiveAddOptionDisabled,
  resolveKooFoldedVisibleSlot,
  shouldRenderKooFoldedSwitch,
  shouldShowKooFoldedSwitch,
  shouldShowKooLiveFailureStopControl,
  shouldShowKooLiveAddPanel
} from '../main/ets/koophone/KooLiveSlotPolicy';
import {
  buildLiveKitPreviewComponentId,
  canClickLiveKitPushButton,
  canToggleLiveKitPush,
  getLiveKitPushButtonColor,
  getLiveKitPushButtonText,
  isLiveKitPushConfigReady,
  LIVEKIT_PUSH_DISABLED,
  LIVEKIT_PUSH_GREEN,
  LIVEKIT_PUSH_RED,
  shouldStopLiveKitPush
} from '../main/ets/push/LiveKitPushPolicy';

export default function localUnitTest() {
  describe('localUnitTest', () => {
    // Defines a test suite. Two parameters are supported: test suite name and test suite function.
    beforeAll(() => {
      // Presets an action, which is performed only once before all test cases of the test suite start.
      // This API supports only one parameter: preset action function.
    });
    beforeEach(() => {
      // Presets an action, which is performed before each unit test case starts.
      // The number of execution times is the same as the number of test cases defined by **it**.
      // This API supports only one parameter: preset action function.
    });
    afterEach(() => {
      // Presets a clear action, which is performed after each unit test case ends.
      // The number of execution times is the same as the number of test cases defined by **it**.
      // This API supports only one parameter: clear action function.
    });
    afterAll(() => {
      // Presets a clear action, which is performed after all test cases of the test suite end.
      // This API supports only one parameter: clear action function.
    });
    it('assertContain', 0, () => {
      // Defines a test case. This API supports three parameters: test case name, filter parameter, and test case function.
      let a = 'abc';
      let b = 'b';
      // Defines a variety of assertion methods, which are used to declare expected boolean conditions.
      expect(a).assertContain(b);
      expect(a).assertEqual(a);
    });
  });

  describe('KooPhone instance auth parser', () => {
    it('parsesSdkStreamingParams', 0, () => {
      const raw = '{"data":{"resource":{"rtc":{"ice_signaling":{"signaling_url":"http://koophone.example.internal:18082","expired_time":null,"ice_servers":[]}},"device_id":"sample-device-id","kp_id":"sample-kp-id"},"device_token":"sample-device-token","streamingId":"sample-streaming-id"},"error_code":"0","error_msg":"OK"}';

      const result = parseKooInstanceAuthResponse(raw);

      expect(result.signalingUrl).assertEqual('http://koophone.example.internal:18082');
      expect(result.token).assertEqual('sample-device-token');
      expect(result.boxId).assertEqual('sample-device-id');
      expect(result.streamingId).assertEqual('sample-streaming-id');
      expect(result.iceServers?.length ?? 0).assertEqual(0);
    });

    it('parsesNumericSuccessCode', 0, () => {
      const raw = '{"data":{"resource":{"rtc":{"ice_signaling":{"signaling_url":"http://koophone.example.internal:18082","expired_time":null,"ice_servers":[]}},"device_id":"sample-device-id","kp_id":"sample-kp-id"},"device_token":"sample-device-token","streamingId":"sample-streaming-id"},"error_code":0,"error_msg":"OK"}';

      const result = parseKooInstanceAuthResponse(raw);

      expect(result.signalingUrl).assertEqual('http://koophone.example.internal:18082');
      expect(result.token).assertEqual('sample-device-token');
      expect(result.boxId).assertEqual('sample-device-id');
    });

    it('throwsWhenDeviceTokenMissing', 0, () => {
      const raw = '{"data":{"resource":{"rtc":{"ice_signaling":{"signaling_url":"http://koophone.example.internal:18082","ice_servers":[]}},"device_id":"sample-device-id"}},"error_code":"0","error_msg":"OK"}';

      let containsExpectedError = false;
      try {
        parseKooInstanceAuthResponse(raw);
      } catch (e) {
        containsExpectedError = String(e).indexOf('data.device_token') >= 0;
      }
      expect(containsExpectedError).assertEqual(true);
    });
  });

  describe('KooPhone instance pool strategy', () => {
    it('selectsFirstBackupThatIsNotCurrentTriedOrOccupied', 0, () => {
      const pool: KooInstancePoolEntry[] = [
        { id: 'dhb4q9j4' },
        { id: 'sKuBZq7c' },
        { id: 'backup-001' }
      ];

      const result = selectNextAvailableKooInstance(pool, {
        currentInstanceId: 'dhb4q9j4',
        triedInstanceIds: ['dhb4q9j4'],
        occupiedInstanceIds: ['sKuBZq7c']
      });

      expect(result).assertEqual('backup-001');
    });

    it('doesNotSelectInstanceOccupiedByOtherLiveRoom', 0, () => {
      const pool: KooInstancePoolEntry[] = [
        { id: 'dhb4q9j4' },
        { id: 'sKuBZq7c' }
      ];

      const result = selectNextAvailableKooInstance(pool, {
        currentInstanceId: 'dhb4q9j4',
        triedInstanceIds: ['dhb4q9j4'],
        occupiedInstanceIds: ['sKuBZq7c']
      });

      expect(result).assertEqual('');
    });

    it('skipsInstancesAlreadyTriedBySamePlatform', 0, () => {
      const pool: KooInstancePoolEntry[] = [
        { id: 'dhb4q9j4' },
        { id: 'sKuBZq7c' },
        { id: 'backup-001' }
      ];

      const result = selectNextAvailableKooInstance(pool, {
        currentInstanceId: 'dhb4q9j4',
        triedInstanceIds: ['dhb4q9j4', 'sKuBZq7c'],
        occupiedInstanceIds: []
      });

      expect(result).assertEqual('backup-001');
    });
  });

  describe('KooPhone expanded live add panel policy', () => {
    it('showsAddPanelOnlyForExpandedInactiveSlotWithAnotherActiveStream', 0, () => {
      const visible = shouldShowKooLiveAddPanel({
        isExpandedScreen: true,
        isFoldedVisibleStoppedSlot: false,
        isSlotLiveActive: false,
        isSlotFailed: false,
        hasAnyLiveActive: true,
        isPendingAdd: false
      });

      expect(visible).assertEqual(true);
    });

    it('doesNotShowAddPanelOnFoldedScreen', 0, () => {
      const visible = shouldShowKooLiveAddPanel({
        isExpandedScreen: false,
        isFoldedVisibleStoppedSlot: false,
        isSlotLiveActive: false,
        isSlotFailed: false,
        hasAnyLiveActive: true,
        isPendingAdd: false
      });

      expect(visible).assertEqual(false);
    });

    it('doesNotShowAddPanelForFailedSlot', 0, () => {
      const visible = shouldShowKooLiveAddPanel({
        isExpandedScreen: true,
        isFoldedVisibleStoppedSlot: false,
        isSlotLiveActive: false,
        isSlotFailed: true,
        hasAnyLiveActive: true,
        isPendingAdd: false
      });

      expect(visible).assertEqual(false);
    });

    it('showsStopControlForFailedStreamUntilUserExits', 0, () => {
      const visible = shouldShowKooLiveFailureStopControl({
        shouldStart: true,
        isSlotFailed: true
      });
      const hiddenAfterExit = shouldShowKooLiveFailureStopControl({
        shouldStart: false,
        isSlotFailed: true
      });
      const hiddenBeforeFailure = shouldShowKooLiveFailureStopControl({
        shouldStart: true,
        isSlotFailed: false
      });

      expect(visible).assertEqual(true);
      expect(hiddenAfterExit).assertEqual(false);
      expect(hiddenBeforeFailure).assertEqual(false);
    });

    it('startsAdditionalSelectionOnlyAfterUserChoosesInactivePlatform', 0, () => {
      const disabled = canStartKooLiveAddSelection({
        isExpandedScreen: true,
        isFoldedVisibleStoppedSlot: false,
        isSlotLiveActive: false,
        isSlotFailed: false,
        hasAnyLiveActive: true,
        isPendingAdd: false
      });
      const enabled = canStartKooLiveAddSelection({
        isExpandedScreen: true,
        isFoldedVisibleStoppedSlot: false,
        isSlotLiveActive: false,
        isSlotFailed: false,
        hasAnyLiveActive: true,
        isPendingAdd: true
      });

      expect(disabled).assertEqual(false);
      expect(enabled).assertEqual(true);
    });

    it('showsAddPanelForFoldedStoppedVisibleSlot', 0, () => {
      const visible = shouldShowKooLiveAddPanel({
        isExpandedScreen: false,
        isFoldedVisibleStoppedSlot: true,
        isSlotLiveActive: false,
        isSlotFailed: false,
        hasAnyLiveActive: true,
        isPendingAdd: false
      });

      expect(visible).assertEqual(true);
    });

    it('keepsSingleFoldedLiveFromShowingAddPanel', 0, () => {
      const visible = shouldShowKooLiveAddPanel({
        isExpandedScreen: false,
        isFoldedVisibleStoppedSlot: false,
        isSlotLiveActive: false,
        isSlotFailed: false,
        hasAnyLiveActive: true,
        isPendingAdd: false
      });

      expect(visible).assertEqual(false);
    });

    it('restartedSlotLeavesAddPanelAndReturnsToSurfaceState', 0, () => {
      const addPanelVisibleAfterRestart = shouldShowKooLiveAddPanel({
        isExpandedScreen: true,
        isFoldedVisibleStoppedSlot: false,
        isSlotLiveActive: true,
        isSlotFailed: false,
        hasAnyLiveActive: true,
        isPendingAdd: false
      });

      expect(addPanelVisibleAfterRestart).assertEqual(false);
    });

    it('enablesStoppedPlatformEvenIfItWasSelectedBefore', 0, () => {
      const disabled = isKooLiveAddOptionDisabled(false);

      expect(disabled).assertEqual(false);
    });

    it('labelsOnlyActivePlatformAsPlaying', 0, () => {
      const inactiveTitle = getKooLiveAddOptionTitle('淘宝直播', false);
      const activeTitle = getKooLiveAddOptionTitle('抖音直播', true);

      expect(inactiveTitle).assertEqual('淘宝直播');
      expect(activeTitle).assertEqual('抖音直播（正在直播中）');
    });

    it('defaultsFoldedDisplayToLeftSlotWhenBothStreamsActive', 0, () => {
      const slot = resolveKooFoldedVisibleSlot(true, true);

      expect(slot).assertEqual('left');
    });

    it('defaultsFoldedDisplayToRightSlotWhenOnlyRightStreamActive', 0, () => {
      const slot = resolveKooFoldedVisibleSlot(false, true);

      expect(slot).assertEqual('right');
    });

    it('showsFoldedSwitchOnlyForFoldedDualStreams', 0, () => {
      const foldedDual = shouldShowKooFoldedSwitch(false, true, true);
      const expandedDual = shouldShowKooFoldedSwitch(true, true, true);
      const foldedSingle = shouldShowKooFoldedSwitch(false, true, false);

      expect(foldedDual).assertEqual(true);
      expect(expandedDual).assertEqual(false);
      expect(foldedSingle).assertEqual(false);
    });

    it('hidesFoldedSwitchWhenFeatureFlagIsDisabled', 0, () => {
      const hidden = shouldRenderKooFoldedSwitch(false, false, true, true);
      const visibleWhenEnabled = shouldRenderKooFoldedSwitch(true, false, true, true);
      const stillHiddenOnExpandedScreen = shouldRenderKooFoldedSwitch(true, true, true, true);

      expect(hidden).assertEqual(false);
      expect(visibleWhenEnabled).assertEqual(true);
      expect(stillHiddenOnExpandedScreen).assertEqual(false);
    });

    it('changesSurfaceComponentIdWhenRevisionIncrements', 0, () => {
      const first = buildKooLiveSurfaceComponentId('taobao', 1);
      const second = buildKooLiveSurfaceComponentId('taobao', 2);

      expect(first).assertEqual('taobao-surface-1');
      expect(second).assertEqual('taobao-surface-2');
      expect(first === second).assertEqual(false);
    });
  });

  describe('LiveKit local camera push policy', () => {
    it('rejectsPlaceholderSfuConfig', 0, () => {
      expect(isLiveKitPushConfigReady('__LIVEKIT_SFU_URL__', 'token')).assertEqual(false);
      expect(isLiveKitPushConfigReady('wss://sfu.example.com', '__LIVEKIT_SFU_TOKEN__')).assertEqual(false);
      expect(isLiveKitPushConfigReady('wss://sfu.example.com', 'jwt-token')).assertEqual(true);
    });

    it('showsStartAndStopButtonStates', 0, () => {
      expect(getLiveKitPushButtonText(false, false)).assertEqual('开始直播推流');
      expect(getLiveKitPushButtonText(true, false)).assertEqual('关闭直播推流');
      expect(getLiveKitPushButtonText(false, true)).assertEqual('推流中...');
      expect(getLiveKitPushButtonText(true, true)).assertEqual('关闭中...');
      expect(getLiveKitPushButtonText(true, false, false)).assertEqual('直播推流中');

      expect(getLiveKitPushButtonColor(false, false)).assertEqual(LIVEKIT_PUSH_GREEN);
      expect(getLiveKitPushButtonColor(true, false)).assertEqual(LIVEKIT_PUSH_RED);
      expect(getLiveKitPushButtonColor(false, true)).assertEqual(LIVEKIT_PUSH_DISABLED);
      expect(getLiveKitPushButtonColor(true, false, false)).assertEqual(LIVEKIT_PUSH_DISABLED);
    });

    it('togglesOnlyAfterPreviewSurfaceReady', 0, () => {
      expect(canToggleLiveKitPush(false, false)).assertEqual(false);
      expect(canToggleLiveKitPush(true, true)).assertEqual(false);
      expect(canToggleLiveKitPush(true, false)).assertEqual(true);
    });

    it('keepsPushButtonClickableAfterPreviewReset', 0, () => {
      expect(canClickLiveKitPushButton(false)).assertEqual(true);
      expect(canClickLiveKitPushButton(true)).assertEqual(false);
      expect(canClickLiveKitPushButton(false, false, false)).assertEqual(true);
      expect(canClickLiveKitPushButton(false, true, false)).assertEqual(false);
    });

    it('changesPreviewComponentIdWhenRevisionIncrements', 0, () => {
      const first = buildLiveKitPreviewComponentId('livekit-preview', 0);
      const second = buildLiveKitPreviewComponentId('livekit-preview', 1);

      expect(first).assertEqual('livekit-preview-0');
      expect(second).assertEqual('livekit-preview-1');
      expect(first === second).assertEqual(false);
    });

    it('stopsPushWhenNoKooPhoneLiveIsActive', 0, () => {
      expect(shouldStopLiveKitPush(true, false)).assertEqual(false);
      expect(shouldStopLiveKitPush(false, true)).assertEqual(false);
      expect(shouldStopLiveKitPush(false, false)).assertEqual(true);
    });
  });
}
