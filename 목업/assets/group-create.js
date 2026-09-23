const createForm=document.querySelector('[data-create-group]');
if(createForm){createForm.addEventListener('submit',(event)=>{event.preventDefault();const name=createForm.querySelector('[name=groupName]').value.trim()||'새 모임';document.querySelector('[data-created-group-name]').textContent=name;document.querySelector('#inviteAfterCreate').hidden=false;const toast=document.querySelector('.toast');toast.textContent=`${name} 모임을 만들었어요. 이제 초대 정보를 생성할 수 있어요.`;toast.classList.add('show');setTimeout(()=>toast.classList.remove('show'),2600)})}

