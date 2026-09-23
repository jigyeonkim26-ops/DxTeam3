(() => {
  const canvas = document.querySelector('#mapCanvas'); if (!canvas) return;
  const CGI_CENTER = [126.877554, 35.110662];
  const places = [
    {name:'\uAD11\uC8FC CGI\uC13C\uD130',meta:'\uAE30\uB85D 4 \u00B7 \uCE5C\uAD6C 3',lat:35.110662,lng:126.877554,href:'features/place.html',kind:'coral'},
    {name:'\uC1A1\uC554\uB3D9 \uD589\uC815\uBCF5\uC9C0\uC13C\uD130',meta:'\uAE30\uB85D 2 \u00B7 \uCE5C\uAD6C 2',lat:35.1113,lng:126.8784,href:'features/place.html',kind:'blue'},
    {name:'\uAD11\uC8FC \uAE40\uCE58\uD0C0\uC6B4',meta:'\uAE30\uB85D 1 \u00B7 \uCE5C\uAD6C 1',lat:35.1058,lng:126.8801,href:'features/place.html',kind:'yellow'}
  ];
  const sheet=document.querySelector('#placeSheet'),name=document.querySelector('#sheetName'),meta=document.querySelector('#sheetMeta'),link=document.querySelector('#sheetLink'),attribution=document.querySelector('#mapAttribution');
  const toast=(message)=>{const target=document.querySelector('.toast');target.textContent=message;target.classList.add('show');setTimeout(()=>target.classList.remove('show'),2600)};
  const show=(place)=>{name.textContent=place.name;meta.textContent=place.meta;link.href=place.href;sheet.classList.add('open')};
  const markerElement=(place,index)=>{const button=document.createElement('button');button.className='place-marker';button.dataset.kind=place.kind;button.type='button';button.setAttribute('aria-label',place.name);button.innerHTML=`<span>${index+1}</span>`;button.addEventListener('click',()=>show(place));return button};
  const search=(callback)=>document.querySelector('#mapSearch').addEventListener('submit',(event)=>{event.preventDefault();const query=event.currentTarget.querySelector('input').value.trim();callback(places.find((place)=>place.name.includes(query))||places[0])});
  const fallback=()=>{canvas.classList.add('map-fallback');places.forEach((place,index)=>{const marker=markerElement(place,index);marker.classList.add('fallback-marker',['one','two','three'][index]);canvas.appendChild(marker)});search(show);document.querySelector('#useGps').addEventListener('click',()=>toast('\uB0B4 \uC704\uCE58\uB294 \uC2E4\uC81C \uC9C0\uB3C4\uAC00 \uB85C\uB4DC\uB41C \uD6C4 \uD45C\uC2DC\uB429\uB2C8\uB2E4.'))};
  if(!window.maplibregl){fallback();return}
  const normal={version:8,sources:{base:{type:'raster',tiles:['https://tile.openstreetmap.org/{z}/{x}/{y}.png'],tileSize:256,attribution:'\u00A9 OpenStreetMap contributors'}},layers:[{id:'base',type:'raster',source:'base'}]};
  const satellite={version:8,sources:{base:{type:'raster',tiles:['https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}'],tileSize:256,attribution:'Tiles \u00A9 Esri'}},layers:[{id:'base',type:'raster',source:'base'}]};
  const map=new maplibregl.Map({container:canvas,style:normal,center:CGI_CENTER,zoom:15});
  map.addControl(new maplibregl.NavigationControl({showCompass:false}),'bottom-right');
  places.forEach((place,index)=>new maplibregl.Marker({element:markerElement(place,index),anchor:'bottom'}).setLngLat([place.lng,place.lat]).addTo(map));
  document.querySelectorAll('[data-map-style]').forEach((button)=>button.addEventListener('click',()=>{const mode=button.dataset.mapStyle;map.setStyle(mode==='satellite'?satellite:normal);attribution.textContent=mode==='satellite'?'Tiles \u00A9 Esri':'\u00A9 OpenStreetMap contributors';document.querySelectorAll('[data-map-style]').forEach((item)=>item.classList.toggle('active',item===button))}));
  search((place)=>{map.flyTo({center:[place.lng,place.lat],zoom:16,essential:true});show(place)});
  let currentMarker;
  document.querySelector('#useGps').addEventListener('click',()=>{if(!navigator.geolocation){toast('\uC774 \uAE30\uAE30\uB294 GPS\uB97C \uC9C0\uC6D0\uD558\uC9C0 \uC54A\uC2B5\uB2C8\uB2E4.');return}toast('\uD604\uC7AC \uC704\uCE58 \uAD8C\uD55C\uC744 \uC694\uCCAD\uD558\uACE0 \uC788\uC5B4\uC694.');navigator.geolocation.getCurrentPosition((position)=>{const center=[position.coords.longitude,position.coords.latitude];map.flyTo({center,zoom:16,essential:true});if(currentMarker)currentMarker.remove();currentMarker=new maplibregl.Marker({color:'#2e85ff'}).setLngLat(center).addTo(map);toast('\uD604\uC7AC \uC704\uCE58\uB85C \uC9C0\uB3C4\uB97C \uC774\uB3D9\uD588\uC5B4\uC694.');},()=>toast('\uC704\uCE58 \uAD8C\uD55C\uC774 \uD544\uC694\uD569\uB2C8\uB2E4. \uC124\uC815\uC5D0\uC11C \uD5C8\uC6A9\uD574 \uC8FC\uC138\uC694.'),{enableHighAccuracy:true,timeout:10000,maximumAge:0})});
})();

