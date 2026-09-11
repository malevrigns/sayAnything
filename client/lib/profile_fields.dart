const genderOptions = {'undisclosed': '不透露', 'male': '男', 'female': '女'};
String genderLabel(dynamic value) => genderOptions[value] ?? '不透露';
