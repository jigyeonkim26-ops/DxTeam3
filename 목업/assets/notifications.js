const storageKey='overlap-notification-settings';
const settings=JSON.parse(localStorage.getItem(storageKey)||'{}');
const toast=(message)=>{const target=document.querySelector('.toast');target.textContent=message;target.classList.add('show');setTimeout(()=>target.classList.remove('show'),2200)};
document.querySelectorAll('[data-notification-setting]').forEach((input)=>{input.checked=settings[input.dataset.notificationSetting] ?? input.checked;input.addEventListener('change',()=>{settings[input.dataset.notificationSetting]=input.checked;localStorage.setItem(storageKey,JSON.stringify(settings));if(input.dataset.notificationSetting==='nearby')toast(input.checked?'장소 근처 리마인드를 켰어요. 실제 위치 권한 연동은 아직 하지 않습니다.':'장소 근처 리마인드를 껐어요.');else toast('알림 설정을 저장했어요.')})});
document.querySelectorAll('[data-sample-notification]').forEach((button)=>button.addEventListener('click',()=>toast('샘플 알림: 민지가 새 기록을 남겼어요.')));

